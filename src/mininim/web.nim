import
    mininim,
    mininim/cli,
    std/httpcore

export
    httpcore

type
    Route = ref object of Facet
        path*: string
        methods*: seq[HttpMethod]

    Serve = ref object of Class

begin Serve:
    method execute*(console: var Console): int =
        result = 0

shape Serve: @[
    Command(
        name: "serve",
        description: "Start the HTTP Server"
    )
]