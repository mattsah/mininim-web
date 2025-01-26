import
    mininim,
    mininim/cli,
    std/os,
    std/strutils,
    std/httpcore,
    std/asynchttpserver,
    std/asyncdispatch

export
    httpcore

type
    Route = ref object of Facet
        path*: string
        methods*: seq[HttpMethod]

    Serve = ref object of Class

begin Serve:
    method start(): AsyncHttpServer =
        var
            server = newAsyncHttpServer()

        server.listen(os.getEnv("WEB_SERVER_PORT", "0").parseInt().Port())

        echo "Server started on http://localhost:", server.getPort().int

        result = server

    method init*(): void =
        var middleware = os.getEnv("WEB_SERVER_MIDDLEWARE", "").strip().split(',')

        for name in middleware:
            when defined(debug):
                echo "Loading middleware: ", name

    method execute*(console: var Console): int =
        var server = this.start()

        while true:
            if server.shouldAcceptRequest():
                waitFor server.acceptRequest(
                    proc(request: Request) {. async .} =
                        await request.respond(Http200, "Here")
                )
            else:
                waitFor sleepAsync(500)

        result = 0



shape Serve: @[
    Command(
        name: "serve",
        description: "Start the HTTP server"
    )
]