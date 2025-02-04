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
    Response* = object
        status*: range[0..599]
        stream*: Stream
        headers*: HttpHeaders

    Middleware* = ref object of Facet
        name*: string

    MiddlewareNext* = proc(request: Request): Response {. gcsafe .}
    MiddlewareHook* = proc(command: Serve, request: Request, pos: int): Response {. nimcall, gcsafe .}

    Handler* = ref object of Class

    Serve* = ref object of Class
        app*: App
        middleware*: seq[Middleware]

begin Handler:
    method handle(request: Request, next: MiddlewareNext): Response {. base, gcsafe .} =
        result        = next(request)
        result.status = 200
        result.stream = newStringStream("Hello Mininim!")

begin Serve:
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
                        (
                            if response.stream == nil:
                                ""
                            else:
                                response.stream.readAll()
                        )
                    )
            )

        echo "Server starting on http://localhost:", port.int
        server.serve(port)

        result = 0

shape Middleware: @[
    Hook(
        swap: Handler,
        call: proc(command: Serve, request: Request, pos: int): Response =
            let
                current = command.app.get(Handler)

            if pos > command.middleware.high:
                result = current.handle(
                    request,
                    proc(request: Request): Response =
                        result = Response(status: 404)
                )

            else:
                result = current.handle(
                    request,
                    proc(request: Request): Response =
                        result = cast[MiddlewareHook](command.middleware[pos].hook)(
                            command,
                            request,
                            pos + 1
                        )
                )
    )
]

shape Handler: @[
    Middleware(
        name: "default"
    )
]

shape Serve: @[
    Delegate(
        hook: proc(app: App): Serve =
            result = Serve.init(app)
    ),
    Command(
        name: "serve",
        description: "Start the HTTP server"
    )
]