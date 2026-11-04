-module(conn_sup).

-behaviour(supervisor).

-export([start_link/0, init/1, start_child/1]).

-spec start_link() -> StartLinkRet when StartLinkRet :: supervisor:startlink_ret().
start_link() -> 
  logger:log(info, "conn_sup starting now ...~n"),
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec init([]) -> {ok, SupFlags, [ChildSpec]} when
    SupFlags :: supervisor:sup_flags(), ChildSpec :: supervisor:child_spec().
init([]) ->
 logger:notice("conn_sup initialized~n"),
 SupFlags = #{
     strategy => simple_one_for_one,
     intensity => 10,
     period => 5
 },
 ChildSpec = #{
     id => connection,
     start => {connection, start_link, [[]]},
     restart => temporary,
     shutdown => 5000,
     type => worker,
     modules => [connection]
 },
 {ok, {SupFlags, [ChildSpec]}}.


-spec start_child(ChildSpec) -> StartChildRet when
    ChildSpec :: supervisor:child_spec(), StartChildRet :: supervisor:startchild_ret().
start_child(ChildSpec) ->
  logger:log(info, "Connection Supervisor starting a child~n"),
  supervisor:start_child(?MODULE, ChildSpec).
