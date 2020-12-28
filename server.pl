:- use_module(library(http/http_server)).
:- use_module(library(lists)).
:- use_module(library(dcgs)).
:- use_module(library(format)).

text_handler(Request, Response) :-
    http_status_code(Response, 200),
    http_body(Response, text("Welcome to Scryer Prolog!")).

sample_handler(Request, Response) :-
    http_headers(Request, Headers),
    member("user-agent"-UserAgent, Headers),
    http_body(Response, text(UserAgent)).

sample_body_handler(Request, Response) :-
    http_body(Request, binary(Body)),
    http_body(Response, binary(Body)),
    http_headers(Response, ["content-type"-"application/json"]).

text_echo_handler(Request, Response) :-
    http_body(Request, text(TextBody)),
    http_body(Response, text(TextBody)).

parameter_handler(User, Request, Response) :-
    http_body(Response, text(User)).

redirect(Request, Response) :-
    http_redirect(Response, "/").

search(Request, Response) :-
    http_query(Request, "q", SearchTerm),
    phrase(format_("Search term: ~s", [SearchTerm]), ResponseText),
    http_body(Response, text(ResponseText)).

file(Request, Response) :-
    http_body(Response, file('/home/aarroyoc/dev/scryer-http-test/comuneros.jpg')).

run :-
    http_listen(7890, [
        get('', text_handler),
        get('user-agent', sample_handler),
        post(echo, sample_body_handler),
        post('echo-text', text_echo_handler),
        get(user/User, parameter_handler(User)),
        get(redirectme, redirect),
        get(search, search),
        get(file, file)
    ]).