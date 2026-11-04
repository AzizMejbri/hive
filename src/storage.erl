-module(storage).

%% Users
-export([create_user/3, get_user/1, get_user_by_name/1,
         list_users/0, update_last_connected/1, delete_user/1]).

%% Channels
-export([create_channel/1, get_channel/1, get_channel_by_name/1,
         list_channels/0, delete_channel/1]).

%% Subscriptions
-export([subscribe/2, unsubscribe/2, is_subscribed/2,
         list_subscriptions/1, list_subscribers/1]).

%% Friendships
-export([befriend/2, unfriend/2, are_friends/2, list_friends/1]).

%% Messages
-export([post_message/3, get_message/1, edit_message/2, delete_message/1,
         messages_in/2, messages_before/3, message_count/1]).

-include("../include/hive.hrl").

%%====================================================================
%% Users
%%====================================================================


-spec create_user(Name, Email, Gender) -> {ok, User} when
    Name :: binary(), Email :: binary(), Gender :: gender(),
    User :: user().
create_user(Name, Email, Gender) ->
    txn(fun() ->
            User = #user{id           = new_id(),
                       name           = Name,
                       email          = Email,
                       gender         = Gender,
                       created_at     = now_ms(),
                       last_connected = undefined},
            ok = mnesia:write(User),
            {ok, User}
    end).

-spec get_user(Id) -> {ok, User} | {error, Reason} when
    Id :: user_id(), User :: user(), Reason :: atom().
get_user(Id) ->
    txn(fun() ->
        case mnesia:read(user, Id) of
            [U] -> {ok, U};
            []  -> {error, not_found}
        end
    end).

-spec get_user_by_name(Name) -> {ok, User} | {error, Reason} when
    Name :: binary(), User :: user(), Reason :: atom().
get_user_by_name(Name) ->
    txn(fun() -> 
      case find_users_by_name(Name) of 
        {ok, [U | _]} -> {ok, U};
        {ok, []}-> {error, not_found}
      end
    end).

-spec list_users() -> {ok, [user()]}.
list_users() ->
    txn(fun() -> {ok, mnesia:match_object(#user{_ = '_'})} end).

-spec update_last_connected(Id) -> {ok, User} | {error, Reason} when
    Id :: user_id(), User :: user(), Reason :: atom().
update_last_connected(Id) ->
    txn(fun() ->
        case mnesia:read(user, Id) of
            [U] ->
                ok = mnesia:write(U#user{last_connected = now_ms()}),
                {ok, U};
            [] ->
                {error, not_found}
        end
    end).

-spec delete_user(user_id()) -> {ok, deleted} | {error, not_found}.
delete_user(Id) ->
    txn(fun() ->
        case mnesia:read(user, Id) of
            [_] -> ok = mnesia:delete({user, Id}), {ok, deleted};
            []  -> {error, not_found}
        end
    end).

-spec find_users_by_name(Name) -> {ok, [User]} when
    Name :: binary(), User :: user(). 
find_users_by_name(Name) ->
  {ok, mnesia:match_object(#user{id = '_', name = Name, _ = '_'})}.
%%====================================================================
%% Channels
%%====================================================================

-spec create_channel(Name) -> {ok, Channel} | {error, Reason} when
    Name :: binary(), Channel :: channel(),
    Reason :: {already_exists, {channel, name, binary()}} | term().
create_channel(Name) ->
    txn(fun() ->
        case find_channels_by_name(Name) of
            {ok, [_|_]} ->
                {error, {already_exists, {channel, name, Name}}};
            {ok, []} ->
                Ch = #channel{id = new_id(), name = Name, created_at = now_ms()},
                ok = mnesia:write(Ch),
                {ok, Ch}
        end
    end).

-spec get_channel(Id) -> {ok, Channel} | {error, Reason} when
    Id :: channel_id(), Channel :: channel(), Reason :: not_found | term().
get_channel(Id) ->
    txn(fun() ->
        case mnesia:read(channel, Id) of
            [C] -> {ok, C};
            []  -> {error, not_found}
        end
    end).

-spec get_channel_by_name(Name) -> {ok, Channel} | {error, Reason} when
    Name :: binary(), Channel :: channel(), Reason :: not_found | term().
get_channel_by_name(Name) ->
    txn(fun() ->
        case find_channels_by_name(Name) of
            {ok, [C | _]} -> {ok, C};
            {ok, []}      -> {error, not_found}
        end
    end).

-spec list_channels() -> {ok, [channel()]}.
list_channels() ->
    txn(fun() -> {ok, mnesia:match_object(#channel{_ = '_'})} end).

-spec delete_channel(Id) -> {ok, deleted} | {error, Reason} when
    Id :: channel_id(), Reason :: not_found | term().
delete_channel(Id) ->
    txn(fun() ->
        case mnesia:read(channel, Id) of
            [_] -> ok = mnesia:delete({channel, Id}), {ok, deleted};
            []  -> {error, not_found}
        end
    end).

-spec find_channels_by_name(binary()) -> {ok, [channel()]}.
find_channels_by_name(Name) ->
  {ok, mnesia:read(channel, Name)}.

%%====================================================================
%% Subscriptions
%%====================================================================

-spec subscribe(UserId, ChannelId) -> {ok, Key} | {error, Reason} when
    UserId :: user_id(), ChannelId :: channel_id(),
    Key :: {user_id(), channel_id()},
    Reason :: already_subscribed | term().
subscribe(UserId, ChannelId) ->
    txn(fun() ->
        Key = {UserId, ChannelId},
        case mnesia:read(subscription, Key) of
            [_] -> {error, already_subscribed};
            []  ->
                ok = mnesia:write(#subscription{key = Key,
                                                subscribed_at = now_ms()}),
                {ok, Key}
        end
    end).

-spec unsubscribe(UserId, ChannelId) -> {ok, deleted} | {error, Reason} when
    UserId :: user_id(), ChannelId :: channel_id(), Reason :: not_found | term().
unsubscribe(UserId, ChannelId) ->
    txn(fun() ->
        Key = {UserId, ChannelId},
        case mnesia:read(subscription, Key) of
            [_] -> ok = mnesia:delete({subscription, Key}), {ok, deleted};
            []  -> {error, not_found}
        end
    end).

-spec is_subscribed(UserId, ChannelId) -> {ok, boolean()} | {error, term()} when
    UserId :: user_id(), ChannelId :: channel_id().
is_subscribed(UserId, ChannelId) ->
    txn(fun() ->
        case mnesia:read(subscription, {UserId, ChannelId}) of
            [_] -> {ok, true};
            []  -> {ok, false}
        end
    end).

-spec list_subscriptions(UserId) -> {ok, [{ChannelId, timestamp()}]} when
    UserId :: user_id(), ChannelId :: channel_id().
list_subscriptions(UserId) ->
    txn(fun() ->
        Subs = mnesia:foldl(
            fun(#subscription{key = {U, C}, subscribed_at = T}, Acc) ->
              if
                U == UserId -> [{C, T} | Acc];
                true -> Acc
              end
            end, [], subscription),
        {ok, Subs}
    end).

-spec list_subscribers(ChannelId) -> {ok, [{UserId, timestamp()}]} when
    ChannelId :: channel_id(), UserId :: user_id().
list_subscribers(ChannelId) ->
    txn(fun() ->
        Users = mnesia:foldl(
            fun(#subscription{key = {U, C}, subscribed_at = T}, Acc) ->
                if
                  C == ChannelId -> [{U, T} | Acc];
                  true -> Acc
                end
            end, [], subscription),
        {ok, Users}
    end).

%%====================================================================
%% Friendships
%%====================================================================

-spec befriend(UserA, UserB) -> {ok, Friendship} | {error, Reason} when
    UserA :: user_id(), UserB :: user_id(), Friendship :: friendship(),
    Reason :: already_friends | cannot_friend_self | term().
befriend(UserA, UserB) when UserA =/= UserB ->
    {Min, Max} = {min(UserA, UserB), max(UserA, UserB)},
    txn(fun() ->
        case mnesia:read(friendship, {Min, Max}) of
            [_] -> {error, already_friends};
            []  ->
                F = #friendship{key = {Min, Max}, friends_since = now_ms()},
                ok = mnesia:write(F),
                {ok, F}
        end
    end);
befriend(_, _) ->
    {error, cannot_friend_self}.

-spec unfriend(UserA, UserB) -> {ok, deleted} | {error, Reason} when
    UserA :: user_id(), UserB :: user_id(), Reason :: not_found | term().
unfriend(UserA, UserB) ->
    {Min, Max} = {min(UserA, UserB), max(UserA, UserB)},
    txn(fun() ->
        case mnesia:read(friendship, {Min, Max}) of
            [_] -> ok = mnesia:delete({friendship, {Min, Max}}), {ok, deleted};
            []  -> {error, not_found}
        end
    end).

-spec are_friends(UserA, UserB) -> {ok, boolean()} | {error, term()} when
    UserA :: user_id(), UserB :: user_id().
are_friends(UserA, UserB) ->
    {Min, Max} = {min(UserA, UserB), max(UserA, UserB)},
    txn(fun() ->
        case mnesia:read(friendship, {Min, Max}) of
            [_] -> {ok, true};
            []  -> {ok, false}
        end
    end).

-spec list_friends(UserId) -> {ok, [{UserId, timestamp()}]} when
    UserId :: user_id().
list_friends(UserId) ->
    txn(fun() ->
        Friends = mnesia:foldl(
            fun(#friendship{key = {A, B}, friends_since = S}, Acc) ->
                if
                  UserId == A -> [{B, S} | Acc];
                  UserId == B -> [{A, S} | Acc];
                  true -> Acc
                end
            end, [], friendship),
        {ok, Friends}
    end).

%%====================================================================
%% Messages
%%====================================================================

-spec post_message(Sender, Target, Content) -> {ok, Message} | {error, term()} when
    Sender :: user_id(),
    Target :: {channel, channel_id()} | {dm, user_id()},
    Content :: binary(),
    Message :: message().
post_message(Sender, Target, Content) ->
    txn(fun() ->
        N = new_id(),
        Msg = #message{id                   = N,
                       sender               = Sender,
                       target               = Target,
                       seq                  = N,
                       content              = Content,
                       sent_at              = now_ms(),
                       last_edited          = now_ms(),
                       deleted_for_everyone = false,
                       edited               = false},
        ok = mnesia:write(Msg),
        {ok, Msg}
    end).

-spec get_message(Id) -> {ok, Message} | {error, Reason} when
    Id :: message_id(), Message :: message(), Reason :: not_found | term().
get_message(Id) ->
    txn(fun() ->
        case mnesia:read(message, Id) of
            [M] -> {ok, M};
            []  -> {error, not_found}
        end
    end).

-spec edit_message(Id, NewContent) -> {ok, Message} | {error, Reason} when
    Id :: message_id(), NewContent :: binary(),
    Message :: message(), Reason :: not_found | term().
edit_message(Id, NewContent) ->
    txn(fun() ->
        case mnesia:read(message, Id) of
            [M] ->
                Updated = M#message{content     = NewContent,
                                    edited      = true,
                                    last_edited = now_ms()},
                ok = mnesia:write(Updated),
                {ok, Updated};
            [] ->
                {error, not_found}
        end
    end).

-spec delete_message(Id) -> {ok, Message} | {error, Reason} when
    Id :: message_id(), Message :: message(), Reason :: not_found | term().
delete_message(Id) ->
    txn(fun() ->
        case mnesia:read(message, Id) of
            [M] ->
                Updated = M#message{deleted_for_everyone = true},
                ok = mnesia:write(Updated),
                {ok, Updated};
            [] ->
                {error, not_found}
        end
    end).

-spec messages_in(Target, Limit) -> {ok, [message()]} | {error, term()} when
    Target :: {channel, channel_id()} | {dm, user_id()},
    Limit :: pos_integer().
messages_in(Target, Limit) when is_integer(Limit), Limit > 0 ->
    txn(fun() ->
        All = live_messages(Target),
        Sorted = lists:reverse(lists:keysort(#message.seq, All)),
        {ok, lists:sublist(Sorted, Limit)}
    end).

-spec messages_before(Target, BeforeSeq, Limit) -> {ok, [message()]} | {error, term()} when
    Target :: {channel, channel_id()} | {dm, user_id()},
    BeforeSeq :: non_neg_integer(), Limit :: pos_integer().
messages_before(Target, BeforeSeq, Limit) when is_integer(Limit), Limit > 0 ->
    txn(fun() ->
        All = live_messages(Target),
        Older = [M || M <- All, M#message.seq < BeforeSeq],
        Sorted = lists:reverse(lists:keysort(#message.seq, Older)),
        {ok, lists:sublist(Sorted, Limit)}
    end).

-spec message_count(Target) -> {ok, non_neg_integer()} | {error, term()} when
    Target :: {channel, channel_id()} | {dm, user_id()}.
message_count(Target) ->
    txn(fun() -> {ok, length(live_messages(Target))} end).

-spec live_messages(Target) -> [message()] when
    Target :: {channel, channel_id()} | {dm, user_id()}.
live_messages(Target) ->
    Ms = mnesia:index_read(message, Target, #message.target),
    [M || M <- Ms, not M#message.deleted_for_everyone].

%%====================================================================
%% Helpers
%%====================================================================

-spec txn(Fun) -> Result when
    Fun :: fun(() -> Result).
txn(Fun) ->
    case mnesia:transaction(Fun) of
        {atomic, Result}   -> Result;
        {aborted, Reason}  -> {error, Reason}
    end.

-spec now_ms() -> timestamp().
now_ms() -> erlang:system_time(millisecond).

-spec new_id() -> pos_integer().
new_id() -> erlang:unique_integer([positive, monotonic]).
