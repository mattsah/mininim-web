import
    mininim,
    mininim/web

type
    Public404 = ref object of Class

begin Public404:
    method handle(request: Request, next: MiddlewareNext): Response =
        if os.fileExists("public" & request.uri.path):
            result = Response(
                status: HttpCode(404)
            )
        else:
            result = next(request)

shape Public404: @[
    Middleware(
        name: "public404",
        priority: 50
    )
]
