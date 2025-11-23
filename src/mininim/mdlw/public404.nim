import
    mininim,
    mininim/web

shape HttpServer: @[
    Middleware(
        name: "public404",
        priority: 50,
        call: MiddlewareHook as (
            block:
                if os.fileExists("public" & request.uri.path):
                    result = Response(
                        status: HttpCode(404)
                    )
                else:
                    result = next(request)
        )
    )
]