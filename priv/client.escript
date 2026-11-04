#!/usr/bin/env escript
%%! -pa _build/default/lib/hive/ebin


main([Host, PortStr, User, Pass]) ->
  Port = list_to_integer(PortStr),
  {ok, S} = gen_tcp:connect(Host, Port, [binary, {packet, 4}, {active, false}]),
  ok = gen_tcp:send(S, term_to_binary({login, list_to_binary(User), list_to_binary(Pass)})),
  case gen_tcp:recv(S, 0, 5000) of
    {ok, R} ->
      io:format("login reply: ~p~n", [binary_to_term(R)]),
      loop(S);
    {error, R} ->
      io:format("Error: ~p, retrying in 2 secs...~n", [R]),
      timer:sleep(2000),
      main([Host,PortStr,User,Pass])
  end;

main(_) ->
  io:format("usage: chat_client.escript <host> <port> <user> <pass>~n"),
  halt(1).

loop(S) ->
  case io:get_line("> ") of
    eof ->
      gen_tcp:close(S),
      ok;
    "quit\n" ->
      gen_tcp:close(S),
      ok;
    Line ->
      case parse_line(Line) of
        {ok, Term} ->
          ok = gen_tcp:send(S, term_to_binary(Term)),
          case gen_tcp:recv(S, 0, 5000) of
            {ok, R} ->
              io:format("~p~n", [binary_to_term(R)]),
              loop(S);
            {error, R} ->
              io:format("error: ~p~n", [R]),
              loop(S)
          end;
        {error, Reason} ->
          io:format("error :~p~n", [Reason]),
          loop(S)
      end
  end.


-spec parse_line(Line) -> {ok, Term} | {error, Info} when
    Line :: string(), Term :: term(), Info :: erl_anno:location().
parse_line(Line) ->
  Src = string:trim(Line) ++ ".",
  case erl_scan:string(Src) of 
    {ok, Tokens, _} ->
      case erl_parse:parse_term(Tokens) of
        {ok, Term} -> {ok, Term};
        {error, Info} -> {error, Info}
      end;
    {error, Info, _} -> {error, Info}
  end.
