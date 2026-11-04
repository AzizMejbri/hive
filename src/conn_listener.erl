-module(conn_listener).
-behaviour(gen_server).

-moduledoc """
TCP listener for the `hive` application.

Binds a listen socket on a configured port. If the port is already
in use, asks the OS to pick one instead. Accepts connections from
the gen_server loop via a self-sent `accept` message.
""".

-export_type([server_state/0, listener_opts/0]).

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export([accept_loop/1]).
-export([new_listener_opts/2, new_listener_opts/3]).

-record(server_state, {
  port :: inet:port_number(),
  sock :: gen_tcp:socket()
}).
-record(listener_opts, {
  address       :: inet:ip_address() | inet:hostname(),
  port          :: inet:port_number(),
  backlog = 128 :: non_neg_integer()
}).

-define(NUM_ACCEPTORS, 5).
-define(SLEEP_AFTER_ACCEPT_FAILURE, 100).

-type server_state() :: #server_state{}.
-type listener_opts() :: #listener_opts{}.

-spec start_link(Opts) -> {ok, Pid} | {error, Term} when
                          Opts :: listener_opts(), Pid :: pid(), Term :: term().
start_link(Opts) ->
  logger:log(info, "network_listener starting~n"),
  gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).


-spec init(Opts) -> {ok, State} | {error, Reason} when
                Opts :: listener_opts(), State :: server_state(), Reason :: system_limit | inet:posix().
init(Opts) ->
  Address = Opts#listener_opts.address,
  BackLog = Opts#listener_opts.backlog,
  DefaultPort = application:get_env(hive, default_port, Opts#listener_opts.port),
  LOpts = [binary, {backlog, BackLog}, inet, {ip, Address}],

  case open_listen_socket(DefaultPort, LOpts) of
    {ok, LS, ActualPort} ->
      logger:log(info, "Listening on port ~p ...", [ActualPort]),
      start_acceptors(LS),
      {ok, #server_state{sock = LS, port = ActualPort}};
    {error, Reason} ->
      logger:log(error, "Could not listen on the port ~p due to the following reason: ~p", [DefaultPort, Reason]),
      {stop, Reason}
  end.



handle_info(Msg, State) -> 
  logger:log(info, "Recieved a message: ~p~n", [Msg]),
  {noreply, State}.

handle_call(_Msg, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State)        -> {noreply, State}.


-spec terminate(Reason, State) -> ok when
    Reason :: atom(), State :: server_state().

terminate(Reason, #server_state{sock = LS}) ->
  logger:log(info, "Closing the socket ~p due to reason: ~p", [LS, Reason]),
  gen_tcp:close(LS),
  ok.

-spec spinup_new_conn(Sock) -> {ok, ChildPid} | {spawn_error, Reason} | {bind_error, BEReason }when
      Sock :: gen_tcp:socket(), ChildPid :: supervisor:child(), Reason :: supervisor:startchild_err(),
      BEReason :: closed | not_owner | badarg | inet:posix().

spinup_new_conn(Sock) ->
  case supervisor:start_child(conn_sup, []) of
    {ok, Child, Info} ->
      logger:log(info, "Created a child ~p: ~p~n", [Child, Info]),
      case gen_tcp:controlling_process(Sock, Child) of
        {error, Reason} ->
          logger:log(error, "Failed to bind the socket ~p to the connection of PID <<~p>> ...~nReason: ~p~n", [Sock, Child, Reason]),
          {bind_error, Reason};
        ok -> 
          gen_server:cast(Child, {socket_ready, Sock}),
          {ok, Child}
      end;
    {ok, Child} ->
      logger:log(info, "Created a child ~p~n", [Child]),
      case gen_tcp:controlling_process(Sock, Child) of
        {error, Reason} ->
          logger:log(error, "Failed to bind the socket ~p to the connection of PID <<~p>> ...~nReason: ~p~n", [Sock, Child, Reason]),
          {bind_error, Reason};
        ok -> 
          gen_server:cast(Child, {socket_ready, Sock}),
          {ok, Child}
      end;
    {error, Reason} ->
      logger:log(error, "Error creating a new fiber for the connection due to the following reason: ~p~n", [Reason]),
      gen_tcp:close(Sock),
      {spawn_error, Reason}
  end.


%% constructor for listener_opts

-spec new_listener_opts({address, Address}, {port, Port}, {backlog, BackLog}) -> ListenerOpts when
    Address :: inet:ip_address() | inet:hostname(),
    Port :: inet:port_number(), BackLog :: non_neg_integer(),
    ListenerOpts :: listener_opts().
new_listener_opts({address, Address}, {port, Port}, {backlog, BackLog}) ->
  #listener_opts{backlog = BackLog, 
                 address = Address,
                 port = Port}.
-spec new_listener_opts({address, Address}, {port, Port}) -> ListenerOpts when
    Address :: inet:ip_address() | inet:hostname(),
    Port :: inet:port_number(),
    ListenerOpts :: listener_opts().
new_listener_opts({address, Address}, {port, Port}) ->
  #listener_opts{address = Address,
                 port = Port}.


-spec open_listen_socket(Port, Opts) -> {ok, LS, ActualPort} | {error, Reason} when
    Port :: inet:port_number(), Opts :: [inet:inet_backend() | inet:listen_option()],
    LS :: inet:socket(), ActualPort :: inet:port_number(), Reason :: system_limit | inet:posix().
open_listen_socket(Port, Opts) ->
  case gen_tcp:listen(Port, Opts) of
    {ok, LS} ->
      {ok, ActualPort} = inet:port(LS),
      {ok, LS, ActualPort};
    
    {error, addrinuse} ->
      logger:warning("Port ~p in use, delegating port choice to the os ...", [Port]),
      case gen_tcp:listen(0, Opts) of
        {ok, LS} ->
          {ok, ActualPort} = inet:port(LS),
          {ok, LS, ActualPort};

        {error, Reason} -> {error, Reason}
      end;

    {error, Reason} -> {error, Reason}
  end.


-spec start_acceptors(LS) -> ok when LS :: inet:socket().
start_acceptors(LS) -> 
  [ proc_lib:spawn_link(?MODULE, accept_loop, [LS]) || _ <- lists:seq(1, ?NUM_ACCEPTORS) ],
  ok.

-spec accept_loop(LS) -> ok when LS :: inet:socket().
accept_loop(LS) -> 
  case gen_tcp:accept(LS) of
    {ok, Socket} ->
      logger:log(info, "Accepted connection on ~p", [Socket]),
      try spinup_new_conn(Socket)
      catch CLASS:REASON:STACK ->
        logger:log(error, "Failed spinning up a new subprocess for ~p: ~p:~p~n~p~n", [LS, CLASS, REASON, STACK]),
        gen_tcp:close(Socket)
      end,
      accept_loop(LS);

    {error, closed} -> ok;

    {error, Reason} ->
      logger:log(error, "Accepting failed due to the following reason: ~p", [Reason]),
      timer:sleep(?SLEEP_AFTER_ACCEPT_FAILURE),
      accept_loop(LS)
  end.

