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

    MiddlewareNext* = proc(request: Request): Response {. closure, gcsafe .}
    MiddlewareHook* = proc(HttpServer: HttpServer, request: Request, pos: int): Response {. closure, gcsafe .}

    HttpServer* = ref object of Class
        middleware*: seq[Middleware]

    Response* = object
        status*: HttpCode
        stream*: Stream
        headers*: HttpHeaders

begin Request:
    discard

begin Request:
    method get*(name: string, default: string = ""): string {. base .} =
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
        call: proc(server: HttpServer, request: Request, pos: int): Response {. closure .}=
            let
                head = this.app.get(shape)
                next = proc(request: Request): Response =
                    if pos > server.middleware.high:
                        result = Response(status: HttpCode(404))
                    else:
                        result = MiddlewareHook.value(server.middleware[pos].call)(
                            server,
                            request,
                            pos + 1
                        )

            result = head.handle(request, next)
    )
]

begin Handler:
    method handle*(request: Request, next: MiddlewareNext): Response {. base .} =
        result        = next(request)
        result.status = HttpCode(200)
        result.stream = newStringStream("Hello Mininim!")

shape Handler: @[
    Middleware(
        name: "default"
    )
]

begin HttpServer:
    method run*(): int {. base .} =
        let
            port = Port(os.getEnv("WEB_SERVER_PORT", "31337").parseInt())
            server = newServer(
                workerThreads = os.getEnv("WEB_SERVER_WORKERS", "128").parseInt(),
                handler = proc(request: Request) {. gcsafe .} =
                    let
                        response = MiddlewareHook.value(this.middleware[0].call)(
                            this,
                            request,
                            1 # There is always at least one middleware, so we start this at 1
                              # to ensure that the next callback generated in the Middleware Hook
                              # will return a 404 appropriately.
                        )

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

    method execute(console: Console): int {. base .} =
        result = this.run()

shape HttpServer: @[
    Delegate(),
    Command(
        name: "serve",
        description: "Start the HTTP Server"
    )
]