-module(mnesia_owner).

-behaviour(gen_server).
-include("hive.hrl").

-export([start_link/0, init/1]).
-export([handle_info/2, handle_cast/2, handle_call/3]).
-export([wait_ready/1]).

-spec ensure_schema() -> mnesia:result().
ensure_schema() ->
  case mnesia:create_schema([node()]) of
    ok ->
      logger:log(info, "Mnesia schema created on node ~p successfuly!", [node()]),
      ok;
    {error, {_, {already_exists, _}}} ->
      logger:log(info, "Mnesia schema already exists on node ~p", [node()]),
      ok;
    {error, Reason} ->
      logger:log(error, "Failed to create mnesia schema on node ~p ...", [node()]),
      {error, Reason}
  end.

-spec start_mnesia() -> mnesia:result().
start_mnesia() ->
  case mnesia:start() of
    ok ->
      logger:log(info, "Mnesia started successfully on node ~p!", [node()]),
      ok;
    {error, Reason} ->
      logger:log(error, "Mnesia startup failed on node ~p due to the following reason: ~p", [
                                                                                             node(),
                                                                                             Reason
                                                                                            ]),
      {error, Reason}
  end.


-spec create_tables() -> ok | {error, Reason} when
    Reason :: mnesia:t_result(ok).
create_tables() ->
    Tables = [
        {user, [
            {attributes, record_info(fields, user)},
            {disc_copies, [node()]},
            {index, [name]}  
        ]},
        {friendship, [
            {attributes, record_info(fields, friendship)},
            {disc_copies, [node()]},
            {type, ordered_set}
        ]},
        {subscription, [
            {attributes, record_info(fields, subscription)},
            {disc_copies, [node()]},
            {type, ordered_set}
        ]},
        {channel, [
            {attributes, record_info(fields, channel)},
            {disc_copies, [node()]}
        ]},
        {message, [
            {attributes, record_info(fields, message)},
            {disc_copies, [node()]},
            {index, [sender, target, sent_at]} 
        ]}
    ],
    lists:foldl(fun create_table_if_not_exists/2, ok, Tables).


-spec create_table_if_not_exists(TableSpec, Acc) -> ok | {error, Reason} when
    TableSpec :: {atom(), mnesia:table()}, Acc :: ok | {error, mnesia:t_result(ok)},
    Reason :: mnesia:t_result(ok).
create_table_if_not_exists(_, {error, _} = Err) ->
  Err; 
create_table_if_not_exists({TableName, TableDef}, ok) ->
  case lists:member(TableName, mnesia:system_info(tables)) of
    true ->
      logger:log(info, "Table ~p already exists", [TableName]),
      ok;

    false ->
      case mnesia:create_table(TableName, TableDef) of
        {atomic, ok} ->
          logger:log(info, "Table ~p created", [TableName]),
          ok;
        {aborted, Reason} ->
          logger:log(error, "Failure during the creation of table ~p, reason: ~p ...", [TableName, Reason]),
          {error, Reason}
      end
  end.

-spec verify_disc_schema() -> ok | {error, ram_schema}.
verify_disc_schema() ->
    case mnesia:table_info(schema, disc_copies) of
        [] ->
            logger:log(error,
                "Schema at ~p is RAM-resident. Either `mnesia` is being "
                "started before mnesia_owner (check hive_app:start/2), or "
                "a stale Mnesia.* directory holds a RAM schema. Delete it "
                "and restart.",
                [mnesia:system_info(directory)]),
            {error, ram_schema};
        _ -> ok
    end.

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
  case ensure_schema() of
    ok ->
      case start_mnesia() of
        ok ->
          case verify_disc_schema() of
            ok ->
              case create_tables() of 
                ok -> 
                  case mnesia:subscribe(system) of   % subscribing for all mnesia's event for proper logging and monitoring
                    {ok, Node} ->
                      logger:log(info, "Table creation suceeded. Node ~p subscribed successfully to mnesia's events!", [Node]);
                    {error, Reason} ->
                      logger:log(warning, "Table creation succeeded. But Failed to subscribe to mnesia's events ... Reason: ~p", [Reason])
                  end,
                  {ok, #{}};
                {error, Reason} ->
                  {stop, {mnesia_table_creation_failure, Reason}}
              end;
              {error, R} -> {stop, {disk_schema_check_failed, R}}
          end;
        {error, Reason} ->
          {stop, {mnesia_start_failure, Reason}}
      end;
    {error, Reason} ->
      {stop, {schema_creation_failure, Reason}}
  end.

-doc """
  what table_info_item() can be, the documentation is pulled straight forom erlang's mnist documentation for table_info/2 items:

   • all. Returns a list of all local table information. Each element is a {InfoItem, ItemVal} tuple.

     New InfoItems can be added and old undocumented InfoItems can be removed without notice.

   • access_mode. Returns the access mode of the table. The access mode can be read_only or read_write.

   • arity. Returns the arity of records in the table as specified in the schema.

   • attributes. Returns the table attribute names that are specified in the schema.

   • checkpoints. Returns the names of the currently active checkpoints, which involve this table on this node.

   • cookie. Returns a table cookie, which is a unique system-generated identifier for the table. The cookie is used internally to ensure that two different table definitions using the same table name cannot accidentally be
     intermixed. The cookie is generated when the table is created initially.

   • disc_copies. Returns the nodes where a disc_copy of the table resides according to the schema.

   • disc_only_copies. Returns the nodes where a disc_only_copy of the table resides according to the schema.

   • index. Returns the list of index position integers for the table.

   • load_node. Returns the name of the node that Mnesia loaded the table from. The structure of the returned value is unspecified, but can be useful for debugging purposes.

   • load_order. Returns the load order priority of the table. It is an integer and defaults to 0 (zero).

   • load_reason. Returns the reason of why Mnesia decided to load the table. The structure of the returned value is unspecified, but can be useful for debugging purposes.

   • local_content. Returns true or false to indicate if the table is configured to have locally unique content on each node.

   • master_nodes. Returns the master nodes of a table.

   • memory. Returns for ram_copies and disc_copies tables the number of words allocated in memory to the table on this node. For disc_only_copies tables the number of bytes stored on disc is returned.

   • ram_copies. Returns the nodes where a ram_copy of the table resides according to the schema.

   • record_name. Returns the record name, common for all records in the table.

   • size. Returns the number of records inserted in the table.

   • snmp. Returns the SNMP struct. [] means that the table currently has no SNMP properties.

   • storage_type. Returns the local storage type of the table. It can be disc_copies, ram_copies, disc_only_copies, or the atom unknown. unknown is returned for all tables that only reside remotely.

   • subscribers. Returns a list of local processes currently subscribing to local table events that involve this table on this node.

   • type. Returns the table type, which is bag, set, or ordered_set.

   • user_properties. Returns the user-associated table properties of the table. It is a list of the stored property records.

   • version. Returns the current version of the table definition. The table version is incremented when the table definition is changed. The table definition can be incremented directly when it has been changed in a schema
     transaction, or when a committed table definition is merged with table definitions from other nodes during startup.

   • where_to_read. Returns the node where the table can be read. If value nowhere is returned, either the table is not loaded or it resides at a remote node that is not running.

   • where_to_write. Returns a list of the nodes that currently hold an active replica of the table.

   • wild_pattern. Returns a structure that can be given to the various match functions for a certain table. A record tuple is where all record fields have value '_'.

""".

handle_call({wait_for_tables, Tables, Timeout}, _From, State) ->
    Reply = mnesia:wait_for_tables(Tables, Timeout),
    {reply, Reply, State};
handle_call(status, _From, State) ->
    Tables  = mnesia:system_info(tables),
    Running = mnesia:system_info(is_running),
    Reply = #{running => Running, tables => Tables,
              directory => mnesia:system_info(directory)},
    {reply, Reply, State};
%% Force a transaction log flush. Rare, but useful before backup.
handle_call(sync_log, _From, State) ->
    Reply = mnesia:sync_log(),
    {reply, Reply, State};
%% Table-level introspection for the metrics reporter / observer.
handle_call({table_info, Table, Items}, _From, State) ->
    Reply = [{Item, mnesia:table_info(Table, Item)} || Item <- Items],
    {reply, Reply, State};
%% Graceful shutdown — called by terminate/2, not by users.
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(Req, _From, State) ->
    {reply, {error, {unknown_request, Req}}, State}.

handle_cast(sync, State) ->
    mnesia:sync_log(),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({mnesia_system_event, Event}, State) ->
    handle_mnesia_event(Event),
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.

handle_mnesia_event({mnesia_up, Node}) ->
    logger:log(info, "Mnesia node up: ~p", [Node]);
handle_mnesia_event({mnesia_down, Node}) ->
    logger:log(warning, "Mnesia node down: ~p", [Node]);
handle_mnesia_event({mnesia_overload, Info}) ->
    logger:log(warning, "Mnesia overloaded: ~p", [Info]);
handle_mnesia_event({inconsistent_database, Ctx, Node}) ->
    logger:log(error, "Inconsistent DB on ~p: ~p", [Node, Ctx]);
handle_mnesia_event(Other) ->
    logger:log(debug, "Mnesia event: ~p", [Other]).


-spec wait_ready(Timeout) -> {reply, Reply, State} when
    Timeout :: timeout(), Reply :: mnesia:result() | {timeout, [mnesia:table()]},
    State :: term().
wait_ready(Timeout) ->
  gen_server:call(?MODULE, {wait_for_tables, all, Timeout}, Timeout + 1000).
