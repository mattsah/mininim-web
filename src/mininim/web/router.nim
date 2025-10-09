import
    mininim,
    mininim/dic,
    mininim/web

export
    web

type
    Route* = ref object of Facet
        path*: string
        methods*: seq[HttpMethod]

    Router* = ref object of Class
        app*: App
        routes*: seq[Route]

    RouteHook = proc(app: App, request: Request): Action {. nimcall .}

    Action* = ref object of Class
        request: Request
        router: Router

begin Action:
    method invoke(): Response {. base .} =
        return Response(status: HttpCode(500))

    method request*(): Request {. base .} =
        return this.request

    method `request=`(request: Request): self {. base .} =
        this.request = request
        return this

    method router*(): Router {. base .} =
        return this.router

    method `router=`(router: Router): self {. base .} =
        this.router = router
        return this

shape Route: @[
    Hook(
        swap: Action,
        call: proc(app: App, request: Request): Action =
            return app.get(Action)
    )
]

begin Router:
    method init*(app: App) {. base, mutator .} =
        this.app = app

    #[
        Adds a route to the router.  This is usually called when the Router is constructed
        as a dependency.

        TODO: Parse routes and use more efficient internal data structure like a tree to make
        lookup faster.
    ]#
    method add*(route: Route) {. base .} =
        this.routes.add(route)


    #[
        Implementation of the middleware handle() method, since our router is just a middleware.
    ]#
    method handle*(request: Request, next: MiddlewareNext): Response {. base .} =
        var
            match: Route

        for route in this.routes:
            if route.path == request.path:
                match = route

        if match == nil:
            result = next(request)
        else:
            let action = cast[RouteHook](match.hook)(this.app, request)

            action.request = request
            action.router = this

            result = action.invoke()

shape Router: @[
    Shared,
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