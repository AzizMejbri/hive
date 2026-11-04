-module(connection).

-behaviour(gen_statem).

-export([start_link/1, notify/2, close/1]).
-export([callback_mode/0, init/1]).
-export([unauthenticated/3, authenticated/3, closing/3, terminate/3]).

-include("../include/hive.hrl").

-type conn_state() :: #{socket => inet  :socket() | undefined,
                        user   => user() | undefined}.

%% -define(AUTH_TIMEOUT, 30000).

start_link(Args) ->
  gen_statem:start_link(?MODULE, Args, []).

notify(Pid, Msg) ->
  gen_statem:cast(Pid, {notify, Msg}).

close(Pid) ->
  gen_statem:cast(Pid, close).

callback_mode() -> state_functions.

init(_) -> 
  {ok, unauthenticated, #{socket => undefined, user => undefined}}.


-spec unauthenticated(RequestKind, Request, StateData) -> keep_state_and_data 
                                                          | {keep_state, NextStateData} 
                                                          | {next_state, NextState, NextStateData} 
                                                          | {stop, normal}
                                                            when
    RequestKind :: gen_statem:event_type(), Request :: term(),
    StateData :: conn_state(), NextState :: atom() , NextStateData :: conn_state().

unauthenticated(cast, {socket_ready, Socket}, State) ->
  ok = inet:setopts(Socket, [{active, once}, {packet, 4}]),
  {keep_state, State#{socket := Socket}};

unauthenticated(info, {tcp, Socket, Bin}, State) ->
  ok = inet:setopts(Socket, [{active, once}]),
  case binary_to_term(Bin) of 
    {login, U, P} -> login(U, P, State);
    _             -> keep_state_and_data
  end;

unauthenticated(info, {tcp_closed, _}, _Data) -> {stop, normal};

unauthenticated(_, _, _) -> keep_state_and_data.

authenticated(cast, {notify, Msg}, State) ->
  logger:log(info, "[Socket: ~p] notify: ~p: ~p~n", [maps:get(socket, State), maps:get(user, State), Msg]),
  keep_state_and_data;

authenticated(cast, close, State) ->
  {next_state, closing, State#{user := undefined}, [{state_timeout, 0, close}]};

authenticated(info,   {tcp_closed, _}, _Data) -> {stop, normal};

authenticated(_, _, _) -> keep_state_and_data.

closing(state_timeout, close, _Data) -> {stop, normal};
closing(_, _, _) -> keep_state_and_data.


-spec terminate(Reason, StateName, State) -> ok when
    Reason :: term(), StateName :: atom(), State :: conn_state().
terminate(Reason, StateName, State) ->
  logger:log(info,
             "Terminating session (no socket): reason=~p state=~p => ~p",
             [Reason, StateName, State]),
  case State of 
    undefined -> ok;

    #{socket := Sock} -> 
      gen_tcp:close(Sock),
      ok
  end.


%% business logic
-spec login(UserName, Password, State) -> keep_state_and_data
                                          | {next_state, NewState, NewData} when
    UserName :: binary(), Password :: binary(), State :: conn_state(),
    NewState :: gen_statem:event_type(), NewData :: conn_state().
login(<<"john">> = UserName, <<"password">>, State) ->
  #{socket := Sock} = State,
  logger:log(info, "Auth successful for user ~p!", [UserName]),
  ok = gen_tcp:send(Sock, term_to_binary({login_ok, UserName})),
  {next_state, authenticated, State#{user := #user{id = 0,
                                                  name = <<"john">>,
                                                  email = <<"john@mail.com">>,
                                                  gender = mail,
                                                  created_at = undefined,
                                                  last_connected = undefined}}};

login(U, P, State) -> 
  #{socket := Sock} = State,
  logger:log(warning, "Auth failed for user `~p`, he used the password `~p`", [U, P]),
  ok = gen_tcp:send(Sock, term_to_binary({login_err, bad_crendentials})),
  keep_state_and_data.
