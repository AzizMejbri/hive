-module(chat_storage_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

-import(conn_listener, [listener_opts/0]).

-spec start_link() -> StartLinkRet when StartLinkRet :: supervisor:startlink_ret().
start_link() ->
  logger:log(info, "Chat Realtime Supervisor started ...~n"),
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  logger:log(info, "Chat Realtime Supervisor initializing ...~n"),
  SupFlags = #{ strategy => rest_for_one,
                intensity => 0,
                period => 1},
  ChildSpecs = [  #{  id => mnesia_owner,
                      start => {mnesia_owner, start_link, []},
                      restart => permanent,
                      shutdown => infinity,
                      type => worker}],
  {ok, {SupFlags, ChildSpecs}}.
  
