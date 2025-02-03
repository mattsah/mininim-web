import
    mininim,
    mininim/dic,
    mininim/web

export
    router

type
    Route* = ref object of Facet
        path*: string
        methods*: seq[HttpMethod]

    RouteHook* = proc(app: App): Response {. nimcall, gcsafe .}

    Action* = ref object of Class

    Router* = ref object of Class
        app*: App
        routes*: seq[Route]

begin Action:
    method invoke*(): Response {. base .}=
        return Response(status: 0)

shape Route: @[
    Hook(
        swap: Action,
        call: proc(app: App): Response =
            let
                action = app.get(Action)

            result = action.invoke()
    )
]

begin Router:
    method init*(app: App) {. base, mutator .} =
        this.app = app

    method add*(route: Route) {. base .} =
        this.routes.add(route)

    method handle*(request: Request, next: MiddlewareNext): Response {. base .} =
        var
            match: Route

        for route in this.routes:
            if route.path == request.path:
                match = route

        if match == nil:
            result = next(request)
        else:
            result = cast[RouteHook](match.hook)(this.app)

            if result.status == 0:
                result.status = 200

shape Router: @[
    Delegate(
        hook: proc(app: App): Router =
            result = Router.init(app)

            for route in app.config.findAll(Route):
                result.add(route)
    ),
    Middleware(
        name: "router"
    )
]