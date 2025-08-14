class LotteryCreator
  def initialize(topic)
    @topic = topic
    @post = topic.first_post
    @user = topic.user
  end

  def create_from_template
    # --- START: 最终的逻辑修复 ---
    # 使用更明确、更不可能出错的写法来检查是否已存在
    if Lottery.find_by(topic_id: @topic.id)
      Rails.logger.warn("LOTTERY_DEBUG: Lottery already exists for topic ##{@topic.id}. Aborting.")
      return
    end
    # --- END: 最终的逻辑修复 ---

    Rails.logger.warn("LOTTERY_DEBUG: LotteryCreator service started for topic ##{@topic.id}.")
    
    raw = @post.raw
    params = parse_raw(raw)

    Rails.logger.warn("LOTTERY_DEBUG: Parsing post ##{@post.id}. Raw params extracted: #{params.inspect}")

    required_keys = [:name, :prize, :winner_count, :draw_type]
    
    if required_keys.any? { |key| params[key].blank? }
      Rails.logger.warn("LOTTERY_DEBUG: Required fields are missing for topic ##{@topic.id}. Params: #{params.inspect}. Aborting.")
      return
    end

    draw_condition_raw = raw[/### 开奖条件\n(.+?)\n\n/, 1]&.strip
    if draw_condition_raw.blank?
        Rails.logger.warn("LOTTERY_DEBUG: Draw condition is missing for topic ##{@topic.id}. Aborting.")
        return
    end

    lottery_params = {
      topic_id: @topic.id,
      post_id: @post.id,
      created_by_id: @user.id,
      name: params[:name],
      prize: params[:prize],
      winner_count: params[:winner_count],
      draw_type: params[:draw_type],
      specific_floors: params[:specific_floors],
      description: params[:description],
      extra_info: params[:extra_info],
      status: Lottery::STATUSES[:running]
    }

    if params[:draw_type] == Lottery::DRAW_TYPES[:by_time]
      lottery_params[:draw_at] = Time.zone.parse(draw_condition_raw) rescue nil
      unless lottery_params[:draw_at]
        Rails.logger.warn("LOTTERY_DEBUG: Invalid date format for draw_condition: '#{draw_condition_raw}' in topic ##{@topic.id}. Aborting.")
        return
      end
    else # by_reply
      lottery_params[:draw_reply_count] = draw_condition_raw.to_i
    end

    if Lottery.create(lottery_params)
      add_tag("抽奖中")
      Rails.logger.warn("LOTTERY_DEBUG: Successfully created lottery for topic ##{@topic.id}")
    end
  end

  private

  def parse_raw(raw)
    params = {}
    params[:name] = raw[/### 抽奖名称\n(.+?)\n\n/, 1]&.strip
    params[:prize] = raw[/### 活动奖品\n(.+?)\n\n/, 1]&.strip
    params[:winner_count] = raw[/### 获奖人数\n(.+?)\n\n/, 1]&.to_i
    
    draw_type_str = raw[/### 开奖方式\n(.+?)\n\n/, 1]&.strip
    if draw_type_str == "时间开奖"
      params[:draw_type] = Lottery::DRAW_TYPES[:by_time]
    elsif draw_type_str == "回复数开奖"
      params[:draw_type] = Lottery::DRAW_TYPES[:by_reply]
    end

    params[:specific_floors] = raw[/### 指定中奖楼层 \(可选\)\n(.+?)\n\n/, 1]&.strip
    params[:description] = raw[/### 简单说明 \(可见内容\)\n(.+?)\n\n/, 1]&.strip
    params[:extra_info] = raw[/### 其他说明 \(可选\)\n(.+?)\n\n/, 1]&.strip
    params
  end

  def add_tag(tag_name)
    tag = Tag.find_or_create_by!(name: tag_name)
    DiscourseTagging.tag_topic_by_names(@topic, Guardian.new(Discourse.system_user), [tag_name])
  end
end
