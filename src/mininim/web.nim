import
    mummy,
    mininim,
    mininim/[
        dic,
        cli
    ],
    std/[
        os,
        streams,
        strutils
    ]

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

    Route* = ref object of Facet
        path*: string
        methods*: seq[HttpMethod]

    Serve* = ref object of Class
        app*: App
        middleware*: seq[Middleware]

    MiddlewareNext* = proc(request: Request): Response {. gcsafe .}
    MiddlewareHook* = proc(serve: Serve, request: Request, pos: int): Response {. nimcall, gcsafe .}

begin Middleware:
    method handle(request: Request, next: MiddlewareNext): Response {. base, gcsafe .} =
        result        = next(request)
        result.status = 200
        result.stream = newStringStream("Hello Mininim!")

shape Middleware: @[
    Hook(
        call: proc(serve: Serve, request: Request, pos: int): Response =
            let
                current = serve.app.get(Middleware)

            if pos > serve.middleware.high:
                result = current.handle(
                    request,
                    proc(request: Request): Response =
                        result = (
                            status: 404,
                            headers: @[],
                            stream: newStringStream("")
                        )
                )

            else:
                result = current.handle(
                    request,
                    proc(request: Request): Response =
                        result = cast[MiddlewareHook](serve.middleware[pos].hook)(
                            serve,
                            request,
                            pos + 1
                        )
                )
    ),
    Middleware(
        name: "default"
    )
]

begin Serve:
    method init*(app: App): void {. base, mutator .} =
        this.app = app

        let
            middleware_names = os.getEnv("WEB_SERVER_MIDDLEWARE", "default").strip().split(',')

        for name in middleware_names:
            when defined(debug):
                echo "Registering middleware: ", name

            let
                middleware = this.app.config.findOne(Middleware, (name: name))

            if middleware == nil:
                echo "here"
                echo "Cannot find middleware: ", name
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

        echo "Server starting on http://localhost:", port.int
        server.serve(port)

        result = 0

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