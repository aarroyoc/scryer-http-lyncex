/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Written in December 2020-November 2021 by Adrián Arroyo (adrian.arroyocalle@gmail.com)
   Part of Scryer Prolog

   This library provides an starting point to build HTTP server based applications.
   It currently implements a subset of HTTP/1.0. It is recommended to put a reverse
   proxy like nginx in front of this server to have access to more advanced features
   (gzip compression, HTTPS, ...)

   Usage
   ==========
   The main predicate of the library is http_listen/2, which needs a port number
    (usually 80) and a list of handlers. A handler is a compound term with the functor
   as one HTTP method (in lowercase) and followed by a Route Match and a predicate
   which will handle the call.

   text_handler(Request, Response) :-
    http_status_code(Response, 200),
    http_body(Response, text("Welcome to Scryer Prolog!")).

   parameter_handler(User, Request, Response) :-
    http_body(Response, text(User)).

   http_listen(7890, [
        get(echo, text_handler),           % GET /echo
        post(user/User, parameter_handler(User)) % POST /user/<User>
   ]).

   Every handler predicate will have at least 2-arity, with Request and Response.
   Although you can work directly with http_request and http_response terms, it is
   recommeded to use the helper predicates, which are easier to understand and cleaner:
   - http_headers(Response/Request, Headers)
   - http_status_code(Responde, StatusCode)
   - http_body(Response/Request, text(Body))
   - http_body(Respone, html(Body))
   - http_body(Response/Request, binary(Body))
   - http_body(Request, form(Form))
   - http_body(Response, file(Filename))
   - http_body(Response, file(Filename, MimeType))
   - http_redirect(Response, Url)
   - http_query(Request, QueryName, QueryValue)

   Some things that are still missing:
   - Read forms in multipart format
   - HTTP Basic Auth
   - Keep-Alive support
   - Session handling via cookies
   - HTML Templating (see teruel)

   I place this code in the public domain. Use it in any way you want.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- module(http_server, [
    http_listen/2,
    http_headers/2,
    http_status_code/2,
    http_body/2,
    http_redirect/2,
    http_query/3,
    url_decode//1
]).

:- use_module(library(charsio)).
:- use_module(library(crypto)).
:- use_module(library(dcgs)).
:- use_module(library(dif)).
:- use_module(library(error)).
:- use_module(library(format)).
:- use_module(library(iso_ext)).
:- use_module(library(lists)).
:- use_module(library(sockets)).
:- use_module(library(time)).

:- meta_predicate http_listen(?, 2).

% Module prefix workaround with meta_predicate
http_listen(Port, Module:Handlers0) :-
    maplist(module_qualification(Module), Handlers0, Handlers),
    http_listen_(Port, Handlers).

module_qualification(M, H0, H) :-
    H0 =.. [Method, Path, Goal],
    H =.. [Method, Path, M:Goal].

% Server initialization
http_listen_(Port, Handlers) :-
    must_be(integer, Port),
    must_be(list, Handlers),
    once(socket_server_open('0.0.0.0':Port, Socket)),
    format("Listening at port ~d\n", [Port]),
    http_loop(Socket, Handlers).

http_loop(Socket, Handlers) :-
    setup_call_cleanup(
        socket_server_accept(Socket, _Client, Stream, [type(binary)]),
        (http_handle_request(Stream, Handlers),!), % cut here because otherwise, close is not called
        close(Stream)
    ),
    http_loop(Socket, Handlers).

% Process a single request
http_handle_request(Stream, Handlers) :-
    read_header_lines(Stream, HeaderChars),
    phrase(http_request_header(Method, URI, _Version, Headers), HeaderChars),
    current_time(Time),
    phrase(format_time("%Y-%m-%d (%H:%M:%S)", Time), TimeString),
    format("~s ~w ~s\n", [TimeString, Method, URI]),
    read_body(Stream, Headers, Body),
    process_request(Handlers, Method, URI, http_request(Headers, Body, _), http_response(StatusCode, BodyOut, HeadersOut)),
    % phrase_to_stream(http_response(StatusCode, BodyOut, HeadersOut), Stream).
    phrase(http_response(StatusCode, BodyOut, HeadersOut), ResponseChars),
    format(Stream, "~s", [ResponseChars]),
    % Some outputs cannot be defined with DCG. On text/html, this part does nothing
    send_binary_response(Stream, BodyOut).

% Read body (if applicable)
read_body(Stream, Headers, Body) :-
    memberchk("content-length"-ContentLengthCs, Headers),
    number_chars(ContentLength, ContentLengthCs),
    read_n_chars(Stream, ContentLength, ByteBody),
    (
        memberchk("content-type"-ContentType, Headers) ->
            (append("text", _, ContentType) ->
                Body = text(ByteBody)
            ;   Body = binary(ByteBody))
        ;   Body = binary(ByteBody)
    ).
read_body(_, _, []).

% Copy all bytes from one stream to another
copy_stream_data(StreamIn, StreamOut) :-
    read_n_chars(StreamIn, _, Bs),
    '$put_chars'(StreamOut, Bs).

% Send binary responses
send_binary_response(Stream, binary(Bytes)) :-
    '$put_chars'(Stream, Bytes).

send_binary_response(Stream, file(Path)) :-
    setup_call_cleanup(
        open(Path, read, StreamIn, [type(binary)]),
        copy_stream_data(StreamIn, Stream),
        close(StreamIn)
    ).
send_binary_response(Stream, file(Path, _)) :-
    send_binary_response(Stream, file(Path)).

send_binary_response(_, _).

% Execute handler and decode queries
process_request(Handlers, Method, URI, Request, Response) :-
    phrase(path(Path, Queries), URI),
    Request = http_request(_, _, Queries),
    once(match_handler(Handlers, Method, Path, Handler)),
    (
        call(Handler, Request, Response) ->
            true
        ;   Response = http_response(500, text("Internal server error"), [])
    ).

% Find handler for given method and path

match_handler(Handlers, Method, "/", Handler) :-
    member(H, Handlers),
    H =.. [Method, /, Handler].
match_handler(Handlers, Method, Path, Handler) :-
    member(H, Handlers),
    copy_term(H, H1),
    H1 =.. [Method, Pattern, Handler],
    \+ var(Pattern),
    phrase(path(Pattern), Path).
match_handler(Handlers, Method, Path, Handler) :-
    member(H, Handlers),
    copy_term(H, H1),
    H1 =.. [Method, Var, Handler],
    var(Var),
    Var = Path.
match_handler(_, _, _, not_found).

not_found(_, http_response(404, text("Not found"), [])).

% Route matching
path(Pattern) -->
    {
        Pattern =.. Parts,
        length(Parts, 3),
        nth0(1, Parts, Pattern0),
        nth0(2, Parts, PartAtom),
        (var(PartAtom) -> Part = PartAtom; atom_chars(PartAtom, Part))
    },
    path(Pattern0),
    "/",
    string_without_('/', Part).

path(Pattern) -->
    {
        Pattern =.. Parts,
        Parts = [PartAtom],
        (var(PartAtom) -> Part = PartAtom; atom_chars(PartAtom, Part))
    },
    "/",
    string_without_('/', Part).

path([]) --> [].

% HTTP 1.0 Protocol coded in DCG

http_request_header(Method, URI, Version, Headers) -->
    request_line(Method, URI, Version),
    request_headers(Headers).

request_line(Method, URI, Version) -->
    method(Method),
    " ",
    string_without_(' ', URI),
    " HTTP/",
    string_without_('\r', Version),
    "\r\n". 

method(options) --> "OPTIONS".
method(get) --> "GET".
method(head) --> "HEAD".
method(post) --> "POST".
method(put) --> "PUT".
method(delete) --> "DELETE".

request_headers([Name-Value|Hs]) -->
    request_header(Name, Value),
    request_headers(Hs).

request_headers([]) --> [].

request_header(LowerHeaderName, HeaderValue) -->
    string_without_(':', HeaderName),
    {
        chars_lower(HeaderName, LowerHeaderName)
    },
    ": ",
    string_without_('\r', HeaderValue),
    "\r\n".

http_response(StatusCode, Body, Headers0) -->
    {
        http_response_content_type(Body, ContentType),
        overwrite_header("connection"-"close", Headers0, Headers1),
        default_header("content-type"-ContentType, Headers1, Headers)
    },
    response_line(StatusCode),
    response_headers(Headers),
    "\r\n",
    response_body(Body).

http_response_content_type(text(_), "text/plain").
http_response_content_type(html(_), "text/html").
http_response_content_type(binary(_), "application/octet-stream").
http_response_content_type(file(_), "application/octet-stream").
http_response_content_type(file(_, Mime), Mime).

response_line(StatusCode) -->
    {
        (var(StatusCode) -> StatusCode = 200; true)
    },
    format_("HTTP/1.0 ~d\r\n", [StatusCode]).

response_headers([Name-Value|Hs]) -->
    response_header(Name, Value),
    response_headers(Hs).

response_headers([]) --> [].

response_header(Name, Value) -->
    format_("~s: ~s\r\n", [Name, Value]).

response_body(text(Body)) -->
    string_(Body).

response_body(html(Body)) -->
    string_(Body).

response_body(_) --> [].

% Header Utils

overwrite_header(Key-Value, [], [Key-Value]).
overwrite_header(Key-Value, [Header|Headers], [Header|HeadersOut]) :-
    Header = Key0-_,
    Key0 \= Key,
    overwrite_header(Key-Value, Headers, HeadersOut).
overwrite_header(Key-Value, [Header|Headers], [NewHeader|Headers]) :-
    Header = Key-_,
    NewHeader = Key-Value.

default_header(Key-Value, [], [Key-Value]).
default_header(Key-Value, [Header|Headers], [Header|HeadersOut]) :-
    Header = Key0-_,
    Key0 \= Key,
    default_header(Key-Value, Headers, HeadersOut).
default_header(Key-Value, [Header|Headers], [NewHeader|Headers]) :-
    Header = Key-_,
    NewHeader = Key-Value.

% Impure IO
read_header_lines(Stream, Hs) :-
    read_line_to_chars(Stream, Cs, []),
    (   Cs == "" -> Hs = []
    ;   Cs == "\r\n" -> Hs = []
    ;   append(Cs, Rest, Hs),
        read_header_lines(Stream, Rest)
    ).

% URL ENCODE

path(Path, Queries) -->
    string_without_('?', Path),
    "?",
    queries(Queries).

path(Path, []) -->
    string_without_(' ', Path).

queries([Key-Value|Queries]) -->
    string_without_('=', Key0),
    {
        phrase(url_decode(Key), Key0)
    },
    "=",
    string_without_('&', Value0),
    {
        phrase(url_decode(Value), Value0)
    },
    "&",
    queries(Queries).

queries([Key-Value]) -->
    string_without_('=', Key0),
    {
        phrase(url_decode(Key), Key0)
    },
    "=",
    string_without_(' ', Value0),
    {
        phrase(url_decode(Value), Value0)  
    }.

% Decodes a UTF-8 URL Encoded string: RFC-1738
url_decode([Char|Chars]) -->
    [Char],
    {
        Char \= '%'
    },
    url_decode(Chars).
url_decode([Char|Chars]) -->
    "%",
    [A],
    [B],
    {
        hex_bytes([A,B], Bytes),
        Bytes = [FirstByte|_],
        FirstByte < 128,
        chars_utf8bytes(Chars0, Bytes),
        Chars0 = [Char]
    },
    url_decode(Chars).
url_decode([Char|Chars]) -->
    "%",
    [A, B],
    "%",
    [C, D],
    {
        hex_bytes([A,B,C,D], Bytes),
        Bytes = [FirstByte|_],
        FirstByte < 224,
        chars_utf8bytes(Chars0, Bytes),
        Chars0 = [Char]
    },
    url_decode(Chars).
url_decode([Char|Chars]) -->
    "%",
    [A, B],
    "%",
    [C, D],
    "%",
    [E, F],
    {
        hex_bytes([A,B,C,D,E,F], Bytes),
        Bytes = [FirstByte|_],
        FirstByte < 240,
        chars_utf8bytes(Chars0, Bytes),
        Chars0 = [Char]
    },
    url_decode(Chars).
url_decode([Char|Chars]) -->
    "%",
    [A, B],
    "%",
    [C, D],
    "%",
    [E, F],
    "%",
    [H, I],
    {
        hex_bytes([A,B,C,D,E,F,H,I], Bytes),
        chars_utf8bytes(Chars0, Bytes),
        Chars0 = [Char]
    },
    url_decode(Chars).

url_decode([]) --> [].

% Common DCGs

string_([X|Xs]) --> [X], string_(Xs).
string_([]) --> [].

string_without_(X, [Y|Ys]) --> 
    [Y],
    {
        dif(X, Y)
    }, string_without_(X, Ys).
string_without_(_, []) --> [].

% Polyfills

% WARNING: This only works for ASCII chars. This code can be modified to support
% Latin1 characters also but a completely different approach is needed for other
% languages. Since HTTP internals are ASCII, this is fine for this usecase.
chars_lower(Chars, Lower) :-
    maplist(char_lower, Chars, Lower).
char_lower(Char, Lower) :-
    char_code(Char, Code),
    ((Code >= 65,Code =< 90) ->
        LowerCode is Code + 32,
        char_code(Lower, LowerCode)
    ;   Char = Lower).

% Helper and recommended predicates

http_headers(http_request(Headers, _, _), Headers).
http_headers(http_response(_, _, Headers), Headers).

http_body(http_request(_, binary(Body), _), text(Body)).
http_body(http_request(Headers, binary(Body), _), form(FormBody)) :- 
    memberchk("content-type"-"application/x-www-form-urlencoded", Headers),
    phrase(queries(FormBody), Body).
http_body(http_request(_, Body, _), Body).
http_body(http_response(_, Body, _), Body).

http_status_code(http_response(StatusCode, _, _), StatusCode).

http_redirect(http_response(307, text("Moved Temporarily"), ["Location"-Uri]), Uri).

http_query(http_request(_, _, Queries), Key, Value) :- member(Key-Value, Queries).