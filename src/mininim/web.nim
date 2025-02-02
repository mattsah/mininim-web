import
    mummy,
    mininim,
    mininim/dic,
    mininim/cli,
    std/os,
    std/streams,
    std/strutils

from std/httpcore import HttpCode, HttpMethod

export
    dic,
    mummy,
    streams,
    HttpMethod

type
    Response* = tuple[
        status: range[0..599],
        headers: HttpHeaders,
        stream: Stream
    ]

    Middleware* = ref object of Facet
        name*: string

    ServeCmd* = ref object of Class
        app*: App
        middleware*: seq[Middleware]

    MiddlewareNext* = proc(request: Request): Response {. gcsafe .}
    MiddlewareHook* = proc(cmd: ServeCmd, request: Request, pos: int): Response {. nimcall, gcsafe .}

begin Middleware:
    method handle(request: Request, next: MiddlewareNext): Response {. base, gcsafe .} =
        result        = next(request)
        result.status = 200
        result.stream = newStringStream("Hello Mininim!")

shape Middleware: @[
    Hook(
        call: proc(cmd: ServeCmd, request: Request, pos: int): Response =
            let
                current = cmd.app.get(Middleware)

            if pos > cmd.middleware.high:
                result = current.handle(
                    request,
                    proc(request: Request): Response =
                        result = (
                            status: 404,
                            headers: emptyHttpHeaders(),
                            stream: newStringStream("")
                        )
                )

            else:
                result = current.handle(
                    request,
                    proc(request: Request): Response =
                        result = cast[MiddlewareHook](cmd.middleware[pos].hook)(
                            cmd,
                            request,
                            pos + 1
                        )
                )
    ),
    Middleware(
        name: "default"
    )
]

begin ServeCmd:
    method init*(app: App): void {. base, mutator .} =
        this.app = app

        let
            middleware_names = os.getEnv("WEB_SERVER_MIDDLEWARE", "default").strip().split(',')

        for name in middleware_names:
            when defined(debug):
                echo "Registering middleware: ", name

            let
                middleware = this.app.config.findAll(Middleware, (name: name))

            if middleware.len == 0:
                echo "Cannot find middleware: ", name
                quit(1)
            elif middleware.len > 1:
                echo "Cannot register ambiguous middleware: ", name
                quit(1)

            this.middleware.add(middleware)

    method execute(console: Console): int {. base .} =
        let
            port = Port(os.getEnv("WEB_SERVER_PORT", "31337").parseInt())
            server = newServer(
                workerThreads = os.getEnv("WEB_SERVER_WORKERS", "128").parseInt(),
                handler = proc(request: Request) =
                    let
                        response = cast[MiddlewareHook](this.middleware[0].hook)(
                            this,
                            request,
                            1
                        )

                    request.respond(
                        response.status,
                        response.headers,
                        response.stream.readAll()
                    )
            )

        echo "ServeCmdr starting on http://localhost:", port.int
        server.serve(port)

        result = 0

shape ServeCmd: @[
    Delegate(
        hook: proc(app: App): ServeCmd =
            result = ServeCmd.init(app)
    ),
    Command(
        name: "serve",
        description: "Start the HTTP server"
    )
]