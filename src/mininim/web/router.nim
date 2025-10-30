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
        params*: seq[string]

    Transformer* = ref object of Facet
        fromUrl: pointer
        toUrl: pointer

    Router* = ref object of Class
        app: App
        tree: RouteTree
        routes: seq[Route]

    RouteHook = proc(app: App, request: Request): Action {. nimcall .}

    RouteList = Table[string, Route]

    RouteTree = ref object of Class
        nodes: Table[string, RouteTree]
        tests: Table[string, RouteTree]
        routes: RouteList

    Action* = ref object of Class
        request: Request
        router: Router

begin RouteTree:
    method map(segment: string, route: Route): string {. base .} =
        result = segment

        var
            parts: seq[string]

        for match in segment.findAll(re"\{\w+(?:\:[^\}]+)?\}"):
            parts = match.strip(chars = {'{', '}'}).split(':')

            when defined(debug):
                echo fmt "Parsed parameter '{parts[0]}' with pattern '{parts[1]}'"

            route.params.add(parts[0])

            if parts.len > 1:
                result = result.replace(match, parts[1])
            else:
                result = result.replace(match, ".+")

    method match(path: string, verb: string, params: var seq[string]): Option[RouteList] {. base .} =
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
                    params.add(parts[0])
                    break

        if child == nil:
            result = none(RouteList)
        elif parts.len == 2:
            result = child.match(parts[1], verb, params)
        else:
            result = some(child.routes)

    method add(path: string, route: Route): void {. base .} =
        let
            parts   = path.split('/', 2)
            pattern = this.map(parts[0], route)

        var
            child: RouteTree


        if pattern != parts[0]:
            if not this.tests.contains(pattern):
                this.tests[pattern] = new RouteTree

            child = this.tests[pattern]
        else:
            if not this.nodes.contains(parts[0]):
                this.nodes[parts[0]] = new RouteTree

            child = this.nodes[parts[0]]

        if parts.len == 2:
            child.add(parts[1], route)
        else:
            for verb in route.methods:
                child.routes[$verb] = route

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
        var
            params: seq[string]

        let
            routes = this.tree.match(request.path, request.httpMethod, params)

        if not isSome(routes):
            result = next(request)
        else:
            if get(routes).contains(request.httpMethod):
                let
                    route  = get(routes)[request.httpMethod]
                    action = cast[RouteHook](route.hook)(this.app, request)

                action.request = request
                action.router = this

                for i in 0..<params.len:
                    if params[i].len > 0:
                        request.pathParams[route.params[i]] = params[i];

                result = action.invoke()
            else:
                result = Response(status: HttpCode(405), headers: HttpHeaders(@[
                    ("Allowed", get(routes).keys.toSeq.join(","))
                ]))

shape Router: @[
    Shared(),
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