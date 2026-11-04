-nominal user_id()    :: integer().
-nominal channel_id() :: integer().
-nominal message_id() :: integer().

-type timestamp() :: integer().   %% ms since epoch
-type gender()    :: male | female.

-export_type([user/0, friendship/0, subscription/0, channel/0, message/0]).
-export_type([user_id/0, channel_id/0, message_id/0, timestamp/0, gender/0]).

-record(user, {
  id             :: user_id(),
  name           :: binary(),
  email          :: binary(),
  password       :: binary() | hidden,
  gender         :: gender(),
  created_at     :: timestamp(),
  last_connected :: timestamp() | undefined,
  privilege      :: admin | user
  %% no status, no channels, no friends — see separate tables
}).

-type user() :: #user{}.

-record(friendship, {
  key           :: {user_id(), user_id()}, % {MinUserId, MaxUserId}
  friends_since :: timestamp()
}).

-type friendship() :: #friendship{}.

-record(subscription, {
  key           :: {user_id(), channel_id()},
  subscribed_at :: timestamp()
}).

-type subscription() :: #subscription{}.

-record(channel, {
  id         :: channel_id(),
  name       :: binary(),
  created_at :: timestamp(),
  admin      :: user_id()
}).

-type channel() :: #channel{}.

-record(message, {
  id                   :: message_id(),
  sender               :: user_id(),
  target               :: {channel, channel_id()} | {dm, user_id()},
  seq                  :: non_neg_integer(),
  content              :: binary(),
  sent_at              :: timestamp(),
  last_edited          :: timestamp(),
  deleted_for_everyone :: boolean(),
  edited               :: boolean()
}).

-type message() :: #message{}.
