import
    mininim,
    mininim/dic,
    mininim/cli,
    mummy/common,
    webby/httpheaders,
    webby/queryparams,
    std/uri,
    std/streams,
    std/algorithm,
    std/nativesockets

from mummy import nil, newServer, serve, respond

from std/httpcore import
    HttpCode,
    HttpMethod

export
    dic,
    uri,
    common,
    streams,
    httpheaders,
    queryparams,
    HttpVersion,
    HttpMethod,
    HttpCode


type

    Middleware* = ref object of Facet
        name*: string
        priority*: int = 500

    MiddlewareHandler* = concept self
        self.handle(Request, MiddlewareNext) is Response

    DefaultMiddlewareHandler* = ref object of Class

    MiddlewareNext* = proc(request: Request): Response {. gcsafe .}
    MiddlewareHook* = proc(request: Request, next: MiddlewareNext): Response {. gcsafe .}

    HttpServer* = ref object of Class
        middleware: seq[Middleware]
        stack: seq[MiddlewareNext]

    Request* = ref object of Class
        base*: mummy.Request
        httpMethod*: HttpMethod
        uri*: Uri

    Response* = ref object of Class
        status*: HttpCode
        stream*: Stream
        headers*: HttpHeaders

converter toRequest(this: mummy.Request): Request =
    result = Request(
        base: this,
        uri: parseUri(this.uri),
        httpMethod: parseEnum[HttpMethod](this.httpMethod)
    )

begin Request:
    method headers*: var HttpHeaders {. base .} =
        result = this.base.headers

    method pathParams*: var PathParams {. base .} =
        result = this.base.pathParams

    method queryParams*: var QueryParams {. base .} =
        result = this.base.queryParams

begin Middleware:
    discard

#[

    TODO: This currently needs to before MiddlewareHandler, otherwise, the default Middleware call is not
    defined and doesn't get imported for MiddlewareHandler's Middlware() facet.
]#
shape Middleware: @[
    Hook(
        call: MiddlewareHook as (
            block:
                static:
                    if not(shape is MiddlewareHandler):
                        raise newException(
                            ValueError,
                            $shape & " cannot register as middlware, must implement MiddlewareHandler or provide `call` overload"
                        )

                result = this.app.get(shape).handle(request, next)
        )
    )
]

begin DefaultMiddlewareHandler:
    method handle*(request: Request, next: MiddlewareNext): Response {. base, gcsafe .} =
        result        = next(request)
        result.status = HttpCode(200)
        result.stream = newStringStream("Hello Mininim!")

shape DefaultMiddlewareHandler: @[
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
                handler = proc(baseRequest: mummy.Request): void =
                    try:
                        let
                            request: Request = baseRequest
                            response: Response = this.stack[0](request)

                        baseRequest.respond(
                            response.status.int,
                            response.headers,
                            (
                                if response.stream == nil:
                                    ""
                                else:
                                    response.stream.readAll()
                            )
                        )

                        response.stream.close()

                    except:
                        baseRequest.respond(
                            HttpCode(500).int,
                            HttpHeaders(@[
                                ("Content-Type", "text/plain; utf-8")
                            ]),
                            getCurrentExceptionMsg() & " : " & $getCurrentException().trace
                        )
            )

        #
        # Set up our middleware stack
        #

        for i in 0..this.middleware.high:
            capture i:
                this.stack.add(
                    MiddlewareNext as (
                        block:
                            result = this.middleware[i][MiddlewareHook](request, this.stack[i + 1])
                    )
                )

        this.stack.add(
            MiddlewareNext as (
                block:
                    result = Response(status: HttpCode(404))
            )
        )

        echo fmt "message[{align($this.type, 3, '0')}]: starting server on http://localhost:{port.int}"
        server.serve(port)

        result = 0

    proc build(app: App): self {. static .} =
        result = self.init()

        var
            middlewares = app.config.findAll(Middleware)

        if middlewares.len == 1:
            let
                default = app.config.findOne(Middleware, (scope: DefaultMiddlewareHandler.type))

            result.middleware.add(default)

            when defined(debug):
                echo fmt "message[{align($default.class, 3, '0')}] registered middleware '{default.name}'"

        else:
            middlewares.sort(
                proc(a, b: Middleware): int =
                    result = a.priority - b.priority
            )

            for middleware in middlewares:
                if middleware.scope != DefaultMiddlewareHandler:
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
