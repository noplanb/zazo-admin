class Metric::Data::ActiveFriendsGrouped < Metric::Data::Base
  def generate
    run_raw_query_on_events(query)
  end

  private

  def query
    <<-SQL
      WITH video_sent AS (
        SELECT DISTINCT
          data->>'sender_id' initiator,
          data->>'receiver_id' target,
          MIN(triggered_at) triggered_at,
          'video_sent' "action"
        FROM events
        WHERE name = '{video,kvstore,received}'
        GROUP BY target_id, data->>'sender_id', data->>'receiver_id'
      ), video_received AS (
        SELECT DISTINCT
          data->>'receiver_id' initiator,
          data->>'sender_id' target,
          MIN(triggered_at) triggered_at,
          'video_received' "action"
        FROM events
        WHERE name = '{video,notification,received}'
        GROUP BY target_id, data->>'sender_id', data->>'receiver_id'
      ), activity AS (
        SELECT *
        FROM video_sent
        UNION SELECT *
              FROM video_received
      ), activity_by_user AS (
        SELECT DISTINCT
          initiator,
          date_trunc('day', triggered_at) triggered_at
        FROM video_sent
      ), messages_sent_received AS (
        SELECT
          initiator,
          COUNT(triggered_at) "count"
        FROM activity
        GROUP BY initiator
      ), active_friends AS (
        SELECT
          initiator,
          COUNT(DISTINCT target) "count"
        FROM activity
        GROUP BY initiator
      ), registered AS (
        SELECT
          initiator_id,
          MIN(triggered_at) registered_at
        FROM events
        WHERE name = '{user,registered}'
        GROUP BY initiator_id
      ), prepared_data AS (
        SELECT
          initiator_id,
          COALESCE(active_friends.count, 0) active_friends,
          COUNT(activity_by_user.initiator)::NUMERIC / COUNT(day)::NUMERIC  percent_active_days,
          COALESCE(messages_sent_received.count, 0) / COUNT(day)::NUMERIC messages_per_days
        FROM registered
          CROSS JOIN generate_series(registered_at, NOW(), '1 day'::INTERVAL) day
          LEFT OUTER JOIN activity_by_user ON activity_by_user.initiator = registered.initiator_id AND
                                              activity_by_user.triggered_at = date_trunc('day', day)
          LEFT OUTER JOIN active_friends ON registered.initiator_id = active_friends.initiator
          LEFT OUTER JOIN messages_sent_received ON registered.initiator_id = messages_sent_received.initiator
        GROUP BY registered.initiator_id, registered_at, active_friends.count, messages_sent_received.count
      ) SELECT
          active_friends,
          COUNT(DISTINCT active_friends.initiator) owners,
          ROUND(AVG(percent_active_days), 4) avg_percent_active_days,
          ROUND(AVG(messages_per_days), 4) avg_messages_per_days
        FROM prepared_data
          LEFT OUTER JOIN active_friends ON active_friends.count = active_friends
        WHERE active_friends > 0
        GROUP BY active_friends
        ORDER BY active_friends
    SQL
  end
end
