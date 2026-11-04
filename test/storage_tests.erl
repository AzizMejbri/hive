-module(storage_tests).

-include_lib("eunit/include/eunit.hrl").

-include("hive.hrl").

%%====================================================================
%% Known bugs that will make some tests fail (fix these first):
%%   1. create_channel: {ok, _} matches both {ok, [C]} and {ok, []},
%%      so a new channel always returns {error, {already_exists, ...}}.
%%   2. edit_message: mnesia:write(messae, M#message{...}) — typo and
%%      wrong arity (write/1 not write/2).
%%   3. create_user: no duplicate-name check (two "alice" allowed).
%%
%% Tests below are the spec — a failure tells you exactly what to fix.
%%====================================================================

storage_test_() ->
  {setup,
   fun setup/0,
   fun cleanup/1,
   fun(_Dir) ->
      [{"users: create / get / list / update / delete", fun users_lifecycle/0},
       {"channels: create / get / list / delete", fun channels_lifecycle/0},
       {"subscriptions: full cycle", fun subscriptions_lifecycle/0},
       {"friendships: full cycle", fun friendships_lifecycle/0},
       {"messages: post / get / edit / delete", fun messages_lifecycle/0},
       {"messages: pagination has no overlap", fun messages_pagination/0}]
   end}.

%%====================================================================
%% Setup / cleanup — isolated Mnesia in a temp dir
%%====================================================================

setup() ->
    os:cmd("rm -rf /tmp/hive_test_*"),

    _ = application:stop(hive),
    _ = mnesia:stop(),
    timer:sleep(100),

    %% Include OS pid + a millisecond timestamp + VM-unique counter.
    %% OS pid differs per rebar3 invocation; timestamp breaks ties when
    %% two VMs land on the same OS pid; unique_integer handles concurrent
    %% fixtures in the same VM.
    Dir = lists:flatten(io_lib:format(
              "/tmp/hive_test_~s_~b_~b",
              [os:getpid(),
               erlang:system_time(millisecond),
               erlang:unique_integer([positive])])),

    ok = filelib:ensure_dir(filename:join(Dir, "dummy")),
    application:set_env(mnesia, dir, Dir),

    io:format("~n~n=== Mnesia dir: ~p~n~n",
              [application:get_env(mnesia, dir)]),

    ok = mnesia:create_schema([node()]),
    ok = mnesia:start(),


  {atomic, ok} =
    mnesia:create_table(user,
                        [{attributes, record_info(fields, user)},
                         {ram_copies, [node()]},
                         {index, [name]}]),
  {atomic, ok} =
    mnesia:create_table(friendship,
                        [{attributes, record_info(fields, friendship)}, {ram_copies, [node()]}]),
  {atomic, ok} =
    mnesia:create_table(subscription,
                        [{attributes, record_info(fields, subscription)}, {ram_copies, [node()]}]),
  {atomic, ok} =
    mnesia:create_table(channel,
                        [{attributes, record_info(fields, channel)}, {ram_copies, [node()]}]),
  {atomic, ok} =
    mnesia:create_table(message,
                        [{attributes, record_info(fields, message)},
                         {ram_copies, [node()]},
                         {index, [target]}]),

  ok =
    mnesia:wait_for_tables(
      mnesia:system_info(tables), 5000),
  Dir.

cleanup(Dir) ->
  mnesia:stop(),
  timer:sleep(100),
  mnesia:delete_schema([node()]),
  os:cmd("rm -rf " ++ Dir),
  ok.

%%====================================================================
%% Users
%%====================================================================

users_lifecycle() ->
  {ok, U} = storage:create_user(<<"alice">>, <<"a@x">>, female),
  ?assert(is_integer(U#user.id)),
  ?assertEqual(<<"alice">>, U#user.name),
  ?assertEqual(female, U#user.gender),

  ?assertMatch({ok, #user{name = <<"alice">>}}, storage:get_user(U#user.id)),
  ?assertMatch({error, not_found}, storage:get_user(999_999_999)),
  ?assertMatch({ok, #user{id = _}}, storage:get_user_by_name(<<"alice">>)),
  ?assertMatch({error, not_found}, storage:get_user_by_name(<<"nobody">>)),

  {ok, All} = storage:list_users(),
  ?assert(lists:any(fun(#user{name = N}) -> N =:= <<"alice">> end, All)),

  timer:sleep(2),
  {ok, U2} = storage:update_last_connected(U#user.id),
  ?assert(is_integer(U2#user.last_connected)),

  ?assertMatch({ok, deleted}, storage:delete_user(U#user.id)),
  ?assertMatch({error, not_found}, storage:get_user(U#user.id)).

%%====================================================================
%% Channels
%%====================================================================

channels_lifecycle() ->
  {ok, Ch} = storage:create_channel(<<"test_chan">>),
  ?assertEqual(<<"test_chan">>, Ch#channel.name),

  ?assertMatch({ok, #channel{name = <<"test_chan">>}}, storage:get_channel(Ch#channel.id)),
  ?assertMatch({ok, #channel{id = _}}, storage:get_channel_by_name(<<"test_chan">>)),
  ?assertMatch({error, not_found}, storage:get_channel(999_999_999)),

  {ok, All} = storage:list_channels(),
  ?assert(lists:any(fun(#channel{id = I}) -> I =:= Ch#channel.id end, All)),

  %% Second create with same name → already_exists
  ?assertMatch({error, {already_exists, _}}, storage:create_channel(<<"test_chan">>)),

  ?assertMatch({ok, deleted}, storage:delete_channel(Ch#channel.id)),
  ?assertMatch({error, not_found}, storage:get_channel(Ch#channel.id)).

%%====================================================================
%% Subscriptions
%%====================================================================

subscriptions_lifecycle() ->
  {ok, U1} = storage:create_user(<<"sub_u1">>, undefined, male),
  {ok, U2} = storage:create_user(<<"sub_u2">>, undefined, female),
  {ok, Ch} = storage:create_channel(<<"sub_chan">>),

  ?assertMatch({ok, {_, _}}, storage:subscribe(U1#user.id, Ch#channel.id)),
  ?assertMatch({error, already_subscribed}, storage:subscribe(U1#user.id, Ch#channel.id)),

  ?assertMatch({ok, true}, storage:is_subscribed(U1#user.id, Ch#channel.id)),
  ?assertMatch({ok, false}, storage:is_subscribed(U2#user.id, Ch#channel.id)),

  ?assertMatch({ok, [{_, _}]}, storage:list_subscriptions(U1#user.id)),
  ?assertMatch({ok, [_]}, storage:list_subscribers(Ch#channel.id)),

  ?assertMatch({ok, deleted}, storage:unsubscribe(U1#user.id, Ch#channel.id)),
  ?assertMatch({error, not_found}, storage:unsubscribe(U1#user.id, Ch#channel.id)),
  ?assertMatch({ok, false}, storage:is_subscribed(U1#user.id, Ch#channel.id)).

%%====================================================================
%% Friendships
%%====================================================================

friendships_lifecycle() ->
  {ok, U1} = storage:create_user(<<"fr_a">>, undefined, male),
  {ok, U2} = storage:create_user(<<"fr_b">>, undefined, female),
  {ok, U3} = storage:create_user(<<"fr_c">>, undefined, male),

  ?assertMatch({ok, #friendship{}}, storage:befriend(U1#user.id, U2#user.id)),
  ?assertMatch({error, already_friends},
               storage:befriend(U2#user.id, U1#user.id)),   %% reversed args
  ?assertMatch({error, cannot_friend_self}, storage:befriend(U1#user.id, U1#user.id)),

  ?assertMatch({ok, true}, storage:are_friends(U1#user.id, U2#user.id)),
  ?assertMatch({ok, true}, storage:are_friends(U2#user.id, U1#user.id)),
  ?assertMatch({ok, false}, storage:are_friends(U1#user.id, U3#user.id)),

  {ok, Friends} = storage:list_friends(U1#user.id),
  ?assert(lists:any(fun({Fid, _}) -> Fid =:= U2#user.id end, Friends)),

  ?assertMatch({ok, deleted}, storage:unfriend(U1#user.id, U2#user.id)),
  ?assertMatch({ok, false}, storage:are_friends(U1#user.id, U2#user.id)).

%%====================================================================
%% Messages — basic
%%====================================================================

messages_lifecycle() ->
  {ok, U} = storage:create_user(<<"msg_author">>, undefined, male),
  Target = {channel, 424242},   %% fake channel id, no channel record needed

  {ok, M} = storage:post_message(U#user.id, Target, <<"hello">>),
  ?assertEqual(<<"hello">>, M#message.content),
  ?assertEqual(Target, M#message.target),
  ?assertEqual(M#message.id, M#message.seq),
  ?assertNot(M#message.deleted_for_everyone),

  ?assertMatch({ok, #message{content = <<"hello">>}}, storage:get_message(M#message.id)),

  {ok, M2} = storage:edit_message(M#message.id, <<"hello edited">>),
  ?assertEqual(<<"hello edited">>, M2#message.content),
  ?assertEqual(true, M2#message.edited),

  {ok, M3} = storage:delete_message(M#message.id),
  ?assertEqual(true, M3#message.deleted_for_everyone),

  {ok, []} = storage:messages_in(Target, 10).

%%====================================================================
%% Messages — pagination
%%====================================================================

messages_pagination() ->
  {ok, U} = storage:create_user(<<"pag_author">>, undefined, male),
  Target = {channel, 12345},

  %% Post 10 messages; collect their seqs
  [begin
     {ok, M} = storage:post_message(U#user.id, Target, integer_to_binary(I)),
     M#message.seq
   end
   || I <- lists:seq(1, 10)],

  %% Page 1: newest 3
  {ok, P1} = storage:messages_in(Target, 3),
  ?assertEqual(3, length(P1)),

  %% Newest-first ordering
  P1Seqs = [M#message.seq || M <- P1],
  ?assertEqual(P1Seqs,
               lists:reverse(
                 lists:sort(P1Seqs))),

  %% Cursor = oldest seq in P1
  OldestSeq = lists:last(P1Seqs),

  %% Page 2: 3 before cursor
  {ok, P2} = storage:messages_before(Target, OldestSeq, 3),
  ?assertEqual(3, length(P2)),

  %% No overlap between P1 and P2
  P2Seqs = [M#message.seq || M <- P2],
  ?assertEqual([], [S || S <- P1Seqs, lists:member(S, P2Seqs)]),

  %% Every seq in P2 is strictly less than the cursor
  ?assert(lists:all(fun(S) -> S < OldestSeq end, P2Seqs)),

  %% Draining the rest: repeated calls eventually return []
  drain(Target, OldestSeq).

drain(Target, Cursor) ->
  case storage:messages_before(Target, Cursor, 3) of
    {ok, []} ->
      ok;
    {ok, Msgs} ->
      drain(Target, lists:last([M#message.seq || M <- Msgs]))
  end.
