import
    mininim,
    mininim/dic,
    mininim/web,
    std/nre

export
    dic,
    web

type
    RouteList = Table[HttpMethod, Route]

    RouteTree = ref object of Class
        nodes: Table[string, RouteTree]
        tests: Table[string, RouteTree]
        routes: RouteList

    RouteHook* = proc(router: Router, request: Request): Response

    Route* = ref object of Facet
        path*: string
        methods*: seq[HttpMethod]
        params*: seq[string]

    Router* = ref object of Class
        tree: RouteTree

    Action* = concept self
        self.invoke() is Response
        self.request is Request
        self.router is Router

    AbstractAction* = ref object of Class
        request*: Request
        router*: Router

begin RouteTree:
    method map(segment: string): string {. base .} =
        result = segment

        var
            parts: seq[string]

        for match in segment.findAll(re"\{\w+(?:\:[^\}]+)?\}"):
            parts = match.strip(chars = {'{', '}'}).split(':')

            if parts.len > 1:
                result = result.replace(match, fmt "(?P<{parts[0]}>{parts[1]})")
            else:
                result = result.replace(match, fmt "(?P<{parts[0]}>.+)")

    method match(request: Request): Route {. base .} =
        var
            branch: RouteTree = this
            found: bool

        for segment in request.uri.path.split('/'):
            found = false

            if branch.nodes.contains(segment):
                found = true
                branch = branch.nodes[segment]
            else:
                for test in branch.tests.keys:
                    let
                        matches = segment.match(test.re)

                    if isSome matches:
                        found = true
                        branch = branch.tests[test]

                        for name, value in get(matches).captures.toTable:
                            request.base.pathParams[name] = value

                        break

            if not found:
                return

        if branch.routes.contains(request.httpMethod):
            result = branch.routes[request.httpMethod]
        else:
            request.headers["Allow"] = branch.routes.keys.toSeq.join(", ")
            result = Route(
                call: RouteHook as (
                    block:
                        result = Response(
                            status: HttpCode(405),
                            headers: HttpHeaders(@[
                                ("Allow", request.headers["Allow"])
                            ])
                        )
                )
            )

    method add(route: Route): void {. base .} =
        var
            branch: RouteTree = this

        for segment in route.path.split('/'):
            let
                pattern = this.map(segment)

            if pattern != segment:
                if not branch.tests.contains(pattern):
                    branch.tests[pattern] = RouteTree()

                branch = branch.tests[pattern]
            else:
                if not branch.nodes.contains(segment):
                    branch.nodes[segment] = RouteTree()

                branch = branch.nodes[segment]

        for verb in route.methods:
            branch.routes[verb] = route

begin AbstractAction:
    method invoke*(): Response {. base, abstract .}

    method get*(name: string, default: string = ""): string {. base .} =
        let
            value = this.request.pathParams.getOrDefault(name, default)

        result = if value != "": value else: default

shape Route: @[
    Hook(
        call: RouteHook as (
            block:
                let
                    action = this.app.get(shape)

                static:
                    if not(shape is Action):
                        raise newException(
                            ValueError,
                            $shape & " cannot register as route, must implement Action or provide `call` overload"
                        )

                action.request = request
                action.router = router

                result = action.invoke()
        )
    )
]

begin Router:
    method init*() {. base .} =
        this.tree = RouteTree.init()

    #[
        Adds a route to the router.  This is usually called when the Router is constructed
        as a dependency.

        TODO: Parse routes and use more efficient internal data structure like a tree to make
        lookup faster.
    ]#
    method add*(route: Route): void {. base .} =
        this.tree.add(route)

    #[
        Implementation of the middleware handle() method, since our router is just a middleware.
    ]#
    method handle*(request: Request, next: MiddlewareNext): Response {. base, gcsafe .} =
        let
            route = this.tree.match(request)

        if route == nil:
            result = next(request)
        else:
            result = route[RouteHook](this, request)

shape Router: @[
    Shared(),
    Delegate(
        call: DelegateHook as (
            block:
                result = shape.init()

                for route in this.app.config.findAll(Route):
                    result.add(route)

                    when defined(debug):
                        echo fmt "message[{align($this.scope, 3, '0')}] registered route: {route.path}"
        )
    ),
    Middleware(
        name: "router",
        priority: 999
    )
]
