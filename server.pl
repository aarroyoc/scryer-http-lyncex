:- use_module(library(http/http_server)).
:- use_module(library(lists)).
:- use_module(library(charsio)).

text_handler(http_request(_,_), http_response(200, text("Welcome to Scryer Prolog!"), [])).

sample_handler(http_request(Headers, _), Response) :-
    member("User-Agent"-UserAgent, Headers),
    Response = http_response(200, text(UserAgent), ["Content-Type"-"text/plain", "Connection"-"Close"]).

sample_body_handler(http_request(_Headers, binary(Body)), http_response(200, binary(Body), ["Content-Type"-"application/json"])) :-
    chars_utf8bytes(CharBody, Body),
    write(CharBody).

text_echo_handler(http_request(_Headers, text(Body)), http_response(200, text(Body), ["Content-Type"-"application/json"])).

run :-
    http_listen(7890, [
        get("/", text_handler),
        get("/user-agent", sample_handler),
        post("/echo", sample_body_handler),
        post("/echo-text", text_echo_handler)
    ]).