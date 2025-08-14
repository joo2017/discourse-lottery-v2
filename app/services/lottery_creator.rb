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
    # 1. 定义必填字段的键
    required_keys = [:name, :prize, :winner_count, :draw_type]
    
    # 2. 检查必填字段是否有任何一个为 nil 或为空
    if required_keys.any? { |key| params[key].blank? }
      Rails.logger.warn("LotteryCreator: Required fields are missing. Params: #{params.inspect}. Aborting.")
      return
    end

    # 3. 额外检查依赖于开奖类型的条件是否有效
    is_time_draw = params[:draw_type] == Lottery::DRAW_TYPES[:by_time]
    is_reply_draw = params[:draw_type] == Lottery::DRAW_TYPES[:by_reply]

    if is_time_draw && params[:draw_at].nil?
      Rails.logger.warn("LotteryCreator: Draw type is by_time but draw_at is nil. Aborting.")
      return
    end

    if is_reply_draw && params[:draw_reply_count].nil?
      Rails.logger.warn("LotteryCreator: Draw type is by_reply but draw_reply_count is nil. Aborting.")
      return
    end
    # --- 校验逻辑修正结束 ---

    lottery = Lottery.new(
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
      extra_info: params[:extra_info],
      status: Lottery::STATUSES[:running]
    )
    
    if lottery.save
      add_tag("抽奖中")
    else
      Rails.logger.error("Lottery creation failed for topic #{@topic.id}: #{lottery.errors.full_messages.join(', ')}")
    end
  end

  private

  def parse_raw(raw)
    params = {}
    params[:name] = raw[/\[lottery-name\](.*?)\[\/lottery-name\]/m, 1]&.strip
    params[:prize] = raw[/\[lottery-prize\](.*?)\[\/lottery-prize\]/m, 1]&.strip
    params[:winner_count] = raw[/\[lottery-winners\](.*?)\[\/lottery-winners\]/m, 1]&.to_i
    
    draw_type_str = raw[/\[lottery-draw-type\](.*?)\[\/lottery-draw-type\]/m, 1]&.strip
    if draw_type_str == "时间开奖"
      params[:draw_type] = Lottery::DRAW_TYPES[:by_time]
      draw_at_str = raw[/\[lottery-condition\](.*?)\[\/lottery-condition\]/m, 1]&.strip
      params[:draw_at] = Time.zone.parse(draw_at_str) rescue nil
    elsif draw_type_str == "回复数开奖"
      params[:draw_type] = Lottery::DRAW_TYPES[:by_reply]
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
