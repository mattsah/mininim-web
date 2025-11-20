import
    mummy,
    mininim,
    mininim/dic,
    mininim/cli,
    std/streams

from std/httpcore import
    HttpCode,
    HttpMethod

export
    dic,
    mummy,
    streams,
    HttpCode,
    HttpMethod

type
    Handler* = ref object of Class

    Middleware* = ref object of Facet
        name*: string
        priority*: int

    MiddlewareNext* = proc(request: Request): Response {. gcsafe .}
    MiddlewareHook* = proc(request: Request, next: MiddlewareNext): Response {. gcsafe .}

    HttpServer* = ref object of Class
        middleware*: seq[Middleware]

    Response* = object
        status*: HttpCode
        stream*: Stream
        headers*: HttpHeaders

begin Request:
    discard

begin Request:
    method get*(name: string, default: string = ""): string =
        let
            value = this.pathParams.getOrDefault(name, default)

        result = if value != "": value else: default

begin Middleware:
    discard

#[

    TODO: This currently needs to before Handler, otherwise, the default Middleware call is not
    defined and doesn't get imported for Handler's Middlware() facet.
]#
shape Middleware: @[
    Hook(
        call: MiddlewareHook as (
            block:
                result = this.app.get(shape).handle(request, next)
        )
    )
]

begin Handler:
    method handle*(request: Request, next: MiddlewareNext): Response {. gcsafe .} =
        result        = next(request)
        result.status = HttpCode(200)
        result.stream = newStringStream("Hello Mininim!")

shape Handler: @[
    Middleware(
        name: "default"
    )
]

begin HttpServer:
    method run*(): int =
        let
            port = Port(os.getEnv("WEB_SERVER_PORT", "31337").parseInt())
            server = newServer(
                workerThreads = os.getEnv("WEB_SERVER_WORKERS", "128").parseInt(),
                handler = RequestHandler as (
                    block:
                        var
                            stack: seq[MiddlewareNext] = @[]
                            response: Response

                        for i in 0..this.middleware.high:
                            capture i:
                                stack.add(
                                    MiddlewareNext as (
                                        block:
                                            result = this.middleware[i][MiddlewareHook](request, stack[i + 1])
                                    )
                                )

                        stack.add(
                            MiddlewareNext as (
                                block:
                                    result = Response(status: HttpCode(404))
                            )
                        )

                        response = stack[0](request)

                        request.respond(
                            response.status.int,
                            response.headers,
                            (
                                if response.stream == nil:
                                    ""
                                else:
                                    response.stream.readAll()
                            )
                        )
                )
            )

        echo fmt "message[{align($this.type, 3, '0')}]: starting server on http://localhost:{port.int}"
        server.serve(port)

        result = 0

    proc build(app: App): self {. static .} =
        result = self.init()

        let
            middlewares = app.config.findAll(Middleware)

        if middlewares.len == 1:
            let
                default = app.config.findOne(Middleware, (scope: Handler.type))

            result.middleware.add(default)

            when defined(debug):
                echo fmt "message[{align($default.class, 3, '0')}] registered middleware '{default.name}'"

        else:
            for middleware in middlewares:
                if middleware.scope != Handler:
                    result.middleware.add(middleware)

                    when defined(debug):
                        echo fmt "message[{align($middleware.class, 3, '0')}] registered middleware '{middleware.name}'"

    method execute(console: Console): int =
        result = this.run()

shape HttpServer: @[
    Delegate(),
    Command(
        name: "serve",
        description: "Start the HTTP Server"
    )
]
