import
    mininim,
    mininim/web,
    mininim/templates,
    parsetoml,
    nre

type
    Pages = ref object of Class

begin Pages:
    method handle(request: Request, next: MiddlewareNext): Response =
        result = next(request)

        if result.status.int != 404:
            return result

        let
            sym = "@"
            reqPath = request.uri.path
            isDirectory = reqPath.endsWith("/")

        var
            path = "resources/pages"
            segments = reqPath.strip(chars = {'/'}).split("/")
            tryTemplate: string
            altTemplate: string


        while segments.len > 0:
            let
                config = path & "/~matchers.toml"
            var
                segment = segments[0]

            segments.delete(0)

            if segment.len > 0 and segment[0] == '.':
                return result

            if os.fileExists(config):
                let
                    matchers = parsetoml.parseFile(config)
                var
                    match: Option[RegexMatch]
                    pattern: string

                for branch, matcher in matchers.getTable():
                    if segment == branch.split("/")[0]:
                        return result

                    if matcher.contains("pattern"):
                        pattern = matcher["pattern"].getStr()
                        match = segment.match(re pattern)
                    else:
                        raise newException(
                            ValueError,
                            fmt "Cannot get pattern in file '{config}', branch: '{branch}'"
                        )

                    if isSome(match):
                        segment = branch
                        if matcher.contains("mapping"):
                            let
                                captures = match.get.captures.toSeq()
                                mapping = matcher["mapping"].arrayVal

                            if mapping.len != captures.len:
                                raise newException(
                                    ValueError,
                                    fmt "Cannot map `{pattern}` in '{config}', captured {captures.len}, mapping {mapping.len}"
                                )

                            for i in 0 .. captures.high:
                                request.pathParams[mapping[i].stringVal] = captures[i].get

                        break
            path = path & "/" & segment.strip(leading = false, chars = {'/'})

            for (key, value) in request.pathParams:
                path = path.replace("&" & key, value)

        if isDirectory:
            tryTemplate = path & "/" & sym & "index.html"
            altTemplate = path.splitPath.head & "/" & sym & path.splitPath.tail & ".html"
        else:
            altTemplate = path & "/" & sym & "index.html"
            tryTemplate = path.splitPath.head & "/" & sym & path.splitPath.tail & ".html"

        if os.fileExists(tryTemplate):
            when defined debug:
                echo fmt "Matched template path '{tryTemplate}'"
            let
                tmpl = this.app.get(TemplateEngine).loadFile(tryTemplate, ())
            tmpl.setGlobal((
                request: request
            ))
            result = tmpl
        elif os.fileExists(altTemplate):
            when defined debug:
                echo fmt "Matched alternative template path '{altTemplate}', redirecting"
            var
                location = deepcopy request.uri

            if isDirectory:
                location.path = reqPath[0..^2]
            else:
                location.path = reqPath & "/"

            result = Response(
                status: HttpCode(301),
                headers: @[
                    ("Location", $location)
                ]
            )
        else:
            discard

shape Pages: @[
    Middleware(
        name: "pages",
        priority: 900
    )
]
