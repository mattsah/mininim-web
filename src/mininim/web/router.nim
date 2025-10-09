import
    mininim,
    mininim/dic,
    mininim/web,
    std/re

export
    web

type
    Route* = ref object of Facet
        path*: string
        methods*: seq[HttpMethod]

    Transformer* = ref object of Facet
        fromUrl: pointer
        toUrl: pointer

    Router* = ref object of Class
        app: App
        tree: RouteTree
        routes: seq[Route]

    RouteHook = proc(app: App, request: Request): Action {. nimcall .}

    RouteTree = ref object of Class
        nodes: Table[string, RouteTree]
        tests: Table[string, RouteTree]
        route: Route

    Action* = ref object of Class
        request: Request
        router: Router

begin RouteTree:
    method map(segment: string): string {. base .} =
        result = segment

    method match(path: string, params: TableRef[string, string]): Route {. base .} =
        let
            parts = path.split('/', 2)

        var
            child: RouteTree

        if this.nodes.contains(parts[0]):
            child = this.nodes[parts[0]]
        else:
            var matches: seq[string] = @[];

            for test in this.tests.keys:
                if parts[0].match(test.re, matches):
                    child = this.tests[test]
                    break

        if child == nil:
            result = nil
        elif parts.len == 2 and parts[1].len > 0:
            result = child.match(parts[1], params)
        else:
            result = this.route

    method add(path: string, route: Route): void {. base .} =
        let
            child = RouteTree.init()
            parts = path.split('/', 2)
            pattern = this.map(parts[0])

        if pattern != parts[0]:
            if not this.tests.contains(pattern):
                this.tests[pattern] = child
        else:
            if not this.nodes.contains(parts[0]):
                this.nodes[parts[0]] = child

        if parts.len == 2 and parts[1].len > 0:
            child.add(parts[1], route)
        else:
            this.route = route


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
        this.tree.add(route.path, route)


    #[
        Implementation of the middleware handle() method, since our router is just a middleware.
    ]#
    method handle*(request: Request, next: MiddlewareNext): Response {. base .} =
        let
            params = newTable[string, string]()
            match  = this.tree.match(request.path, params)

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
            result.tree = RouteTree.init()

            for route in app.config.findAll(Route):
                result.add(route)
    ),
    Middleware(
        name: "router"
    )
]