%%%-------------------------------------------------------------------
%% @doc hive top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(hive_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
  ok = logger:set_primary_config(level, info),
  SupFlags = #{
      strategy => rest_for_one,
      intensity => 0,
      period => 1
  },
  ChildSpecs = [#{  id => chat_storage_sup,
                    start => {chat_storage_sup, start_link, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => supervisor},
                #{  id => chat_realtime_sup,
                    start => {chat_realtime_sup, start_link, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => supervisor}],
  {ok, {SupFlags, ChildSpecs}}.

%% internal functions
