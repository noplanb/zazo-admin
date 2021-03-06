class Metric::Data::MessagesCountBetweenUsers < Metric::Data::Base
  def self.allowed_attributes
    { user_id: { default: nil },
      friends_ids: { default: nil },
      users_ids: { default: nil } }
  end

  def generate
    results.as_json.map { |row| row.delete 'id'; row }
  end

  protected

  def results
    if users_ids
      query, params = reduce_by_packs
      scope = Event.where query, *params
    else
      scope = Event.where query_where,
                          user_id, friends_ids,
                          friends_ids, user_id
    end
    scope.name_overlap(%w(downloaded viewed))
         .group('receiver, sender')
         .select(query_select)
  end

  def reduce_by_packs
    first  = users_ids.shift
    query  = "(#{query_where})"
    params = [first[0], first[1], first[1], first[0]]
    users_ids.keys.each do |key|
      query += 'OR' + "(#{query_where})"
      params.push key, users_ids[key], users_ids[key], key
    end
    [query, params]
  end

  def query_where
    <<-SQL
      data->>'sender_id'     = ? AND
      data->>'receiver_id' IN (?) OR
      data->>'sender_id'   IN (?) AND
      data->>'receiver_id'   = ?
    SQL
  end

  def query_select
    <<-SQL
      data->>'sender_id'   as sender,
      data->>'receiver_id' as receiver,
      COUNT(DISTINCT data->>'video_filename')
    SQL
  end
end
