-module(chat_realtime_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

-import(conn_listener, [listener_opts/0]).

-spec start_link() -> StartLinkRet when StartLinkRet :: supervisor:startlink_ret().
start_link() ->
  logger:log(info, "Chat Realtime Supervisor started ...~n"),
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  logger:log(info, "Chat Realtime Supervisor initializing ...~n"),
  SupFlags = #{ strategy => one_for_one,
                intensity => 0,
                period => 1},
  ChildSpecs = [  #{  id => conn_sup,
                      start => {conn_sup, start_link, []},
                      restart => permanent,
                      shutdown => infinity,
                      type => supervisor},
                  #{  id => conn_listener,
                      start => {conn_listener, start_link, [conn_listener:new_listener_opts({address, {0,0,0,0}}, {port, 6969})]},
                      restart => permanent, shutdown => 5000, type => worker}],
  {ok, {SupFlags, ChildSpecs}}.
  
