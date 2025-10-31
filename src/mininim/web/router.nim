import
    mininim,
    mininim/dic,
    mininim/web,
    std/nre

export
    web

type
    Route* = ref object of Facet
        path*: string
        methods*: seq[HttpMethod]
        params*: seq[string]

    Router* = ref object of Class
        app: App
        tree: RouteTree
        routes: seq[Route]

    RouteHook = proc(router: Router, request: Request): Response {. nimcall, gcsafe .}

    RouteList = Table[string, Route]

    RouteTree = ref object of Class
        nodes: Table[string, RouteTree]
        tests: Table[string, RouteTree]
        routes: RouteList

    Action* = ref object of Class
        request*: Request
        router*: Router

begin RouteTree:
    method map(segment: string, route: Route): string {. base .} =
        result = segment

        var
            parts: seq[string]

        for match in segment.findAll(re"\{\w+(?:\:[^\}]+)?\}"):
            parts = match.strip(chars = {'{', '}'}).split(':')

            route.params.add(parts[0])

            if parts.len > 1:
                result = result.replace(match, fmt "(?P<{parts[0]}>{parts[1]})")
            else:
                result = result.replace(match, fmt "(?P<{parts[0]}>.+)")

    method match(path: string, verb: string, params: var seq[string]): RouteList {. base .} =
        var
            child: RouteTree = nil

        let
            parts = path.split('/', 2)

        if this.nodes.contains(parts[0]):
            child = this.nodes[parts[0]]
        else:
            for test in this.tests.keys:
                let
                    matches = parts[0].match(test.re)

                if isSome matches:
                    child = this.tests[test]

                    for item in get(matches).captures.toSeq:
                        params.add(get(item))

                    break

        if child != nil:
            if parts.len == 2:
                result = child.match(parts[1], verb, params)
            else:
                result = child.routes

    method add(path: string, route: Route): void {. base .} =
        var
            child: RouteTree = nil

        let
            parts   = path.split('/', 2)
            pattern = this.map(parts[0], route)

        if pattern != parts[0]:
            if not this.tests.contains(pattern):
                this.tests[pattern] = RouteTree()

            child = this.tests[pattern]
        else:
            if not this.nodes.contains(parts[0]):
                this.nodes[parts[0]] = RouteTree()

            child = this.nodes[parts[0]]

        if parts.len == 2:
            child.add(parts[1], route)
        else:
            for verb in route.methods:
                child.routes[$verb] = route

begin Action:
    method invoke(): Response {. base .} =
        return Response(status: HttpCode(500))

shape Route: @[
    Hook(
        swap: Action,
        call: proc(router: Router, request: Request): Response =
            let
                action = router.app.get(Action)

            action.request = request
            action.router = router

            result = action.invoke()
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
    method add*(route: Route): void {. base .} =
        this.tree.add(route.path, route)

    #[
        Public getter for the app
    ]#
    method app*(): App {. base .} =
        return this.app

    #[
        Implementation of the middleware handle() method, since our router is just a middleware.
    ]#
    method handle*(request: Request, next: MiddlewareNext): Response {. base .} =
        var
            params: seq[string] = @[]

        let
            routes = this.tree.match(request.path, request.httpMethod, params)

        if routes.len == 0:
            result = next(request)
        else:
            if routes.contains(request.httpMethod):
                let
                    route  = routes[request.httpMethod]

                for i in 0..params.high:
                    if params[i].len > 0:
                        request.pathParams[route.params[i]] = params[i];

                result = cast[RouteHook](route.hook)(this, request)

            else:
                result = Response(status: HttpCode(405), headers: HttpHeaders(@[
                    ("Allowed", routes.keys.toSeq.join(","))
                ]))

shape Router: @[
    Shared(),
    Delegate(
        hook: proc(app: App): Router =
            result = Router.init(app)
            result.tree = RouteTree.init()

            for route in app.config.findAll(Route):
                result.add(route)

                when defined(debug):
                    echo fmt "Registered route: {route.path}"

    ),
    Middleware(
        name: "router"
    )
]