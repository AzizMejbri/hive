-module(connection).

-behaviour(gen_statem).

-export([start_link/1, notify/2, close/1]).
-export([callback_mode/0, init/1]).
-export([unauthenticated/3, authenticated/3, closing/3, terminate/3]).

callback_mode() -> state_functions.

init(_) ->
    {ok, unauthenticated, #{socket => undefined, user => undefined}}.

start_link(Args) ->
    gen_statem:start_link(?MODULE, Args, []).

notify(Pid, Msg) -> gen_statem:cast(Pid, {notify, Msg}).
close(Pid)       -> gen_statem:cast(Pid, close).

%%====================================================================
%% unauthenticated
%%====================================================================

unauthenticated(cast, {socket_ready, Socket}, State) ->
    ok = inet:setopts(Socket, [{active, once}, {packet, 4}]),
    {keep_state, State#{socket := Socket}};

unauthenticated(info, {tcp, Socket, Bin}, #{socket := Socket} = State) ->
    ok = inet:setopts(Socket, [{active, once}]),
    dispatch(decode(Bin), State);

unauthenticated(info, {tcp_closed, _}, _State) -> {stop, normal};
unauthenticated(_, _, _)                       -> keep_state_and_data.

%%====================================================================
%% authenticated
%%====================================================================

authenticated(cast, {notify, Msg}, #{socket := S, user := U} = _State) ->
    logger:log(info, "[Socket: ~p] notify: ~p: ~p", [S, U, Msg]),
    keep_state_and_data;

authenticated(cast, close, State) ->
    {next_state, closing, State#{user := undefined},
     [{state_timeout, 0, close}]};

authenticated(info, {tcp, Socket, Bin}, #{socket := Socket} = State) ->
    ok = inet:setopts(Socket, [{active, once}]),
    dispatch(decode(Bin), State);

authenticated(info, {tcp_closed, _}, _State) -> {stop, normal};
authenticated(_, _, _)                       -> keep_state_and_data.

%%====================================================================
%% closing
%%====================================================================

closing(state_timeout, close, _State) -> {stop, normal};
closing(_, _, _)                      -> keep_state_and_data.

%%====================================================================
%% dispatch — bridges command:handle/2 to gen_statem return values
%%====================================================================

%% logout (when authenticated) replies then closes the socket, per spec.

dispatch({ok, {logout} = Command}, #{user := U} = State) when U =/= undefined ->
    _ = command:handle(Command, State),
    {stop, normal};
dispatch({ok, {logout} = Command}, #{user := undfined} = State) ->
  _ = command:handle(Command, State),
  ok;

dispatch({ok, Command}, State) ->
    case command:handle(Command, State) of
        {ok, #{user := undefined} = NewState} ->
            {next_state, unauthenticated, NewState};
        {ok, NewState} ->
            {next_state, authenticated, NewState};
        {error, Reason} ->
            logger:log(warning, "network error on ~p: ~p", [Command, Reason]),
            {stop, normal}
    end;

dispatch({error, Command}, State) ->
    %% couldn't decode the packet — tell the client and keep going.
    _ = command:send(State, {error, bad_encoding}),
    logger:log(warning, "bad encoding on the packet: ~p", [Command]),
    keep_state_and_data.

%%====================================================================
%% decode — safe untrusted-binary decode
%%====================================================================

decode(Bin) ->
    try binary_to_term(Bin, [safe]) of
        Term -> {ok, Term}
    catch
        error:badarg -> {error, bad_encoding}
    end.

%%====================================================================
%% terminate
%%====================================================================

terminate(Reason, StateName, State) ->
    logger:log(info,
               "Terminating session: reason=~p state=~p data=~p",
               [Reason, StateName, State]),
    case State of
        #{socket := Sock} when Sock =/= undefined -> gen_tcp:close(Sock), ok;
        _                                         -> ok
    end.
