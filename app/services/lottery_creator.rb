class LotteryCreator
  def initialize(topic)
    @topic = topic
    @post = topic.first_post
    @user = topic.user
  end

  def create_from_template
    return if Lottery.exists?(topic_id: @topic.id)
    raw = @post.raw
    params = parse_raw(raw)
    
    # --- 关键校验逻辑修正 ---
    # 定义必填字段
    required_params = [:name, :prize, :winner_count, :draw_type]
    # 检查是否有任何一个必填字段为 nil
    return if required_params.any? { |p| params[p].nil? }
    # 额外检查依赖于 draw_type 的开奖条件是否有效
    return if (params[:draw_type] == :by_time && params[:draw_at].nil?) || \
              (params[:draw_type] == :by_reply && params[:draw_reply_count].nil?)
    # --- 校验逻辑修正结束 ---

    Lottery.create!(
      topic_id: @topic.id,
      post_id: @post.id,
      created_by_id: @user.id,
      name: params[:name],
      prize: params[:prize],
      winner_count: params[:winner_count],
      draw_type: params[:draw_type],
      draw_at: params[:draw_at],
      draw_reply_count: params[:draw_reply_count],
      specific_floors: params[:specific_floors],
      description: params[:description],
      extra_info: params[:extra_info]
    )
    add_tag("抽奖中")
  end

  private

  def parse_raw(raw)
    params = {}
    params[:name] = raw[/\[lottery-name\](.*?)\[\/lottery-name\]/m, 1]&.strip
    params[:prize] = raw[/\[lottery-prize\](.*?)\[\/lottery-prize\]/m, 1]&.strip
    params[:winner_count] = raw[/\[lottery-winners\](.*?)\[\/lottery-winners\]/m, 1]&.to_i
    
    draw_type_str = raw[/\[lottery-draw-type\](.*?)\[\/lottery-draw-type\]/m, 1]&.strip
    if draw_type_str == "时间开奖"
      params[:draw_type] = :by_time
      draw_at_str = raw[/\[lottery-condition\](.*?)\[\/lottery-condition\]/m, 1]&.strip
      params[:draw_at] = Time.zone.parse(draw_at_str) rescue nil
    elsif draw_type_str == "回复数开奖"
      params[:draw_type] = :by_reply
      params[:draw_reply_count] = raw[/\[lottery-condition\](.*?)\[\/lottery-condition\]/m, 1]&.to_i
    end

    params[:specific_floors] = raw[/\[lottery-floors\](.*?)\[\/lottery-floors\]/m, 1]&.strip
    params[:description] = raw[/\[lottery-description\](.*?)\[\/lottery-description\]/m, 1]&.strip
    params[:extra_info] = raw[/\[lottery-extra\](.*?)\[\/lottery-extra\]/m, 1]&.strip

    params
  end

  def add_tag(tag_name)
    tag = Tag.find_or_create_by!(name: tag_name)
    DiscourseTagging.tag_topic_by_names(@topic, Guardian.new(Discourse.system_user), [tag_name])
  end
end
