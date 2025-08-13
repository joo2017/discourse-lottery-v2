class LotteryCreator
  def initialize(topic)
    @topic = topic
    @post = topic.first_post
    @user = topic.user
  end

  def create_from_template
    Rails.logger.warn("LOTTERY_DEBUG: LotteryCreator service started for topic ##{@topic.id}.")
    
    return if Lottery.exists?(topic_id: @topic.id)
    raw = @post.raw
    params = parse_raw(raw)

    Rails.logger.warn("LOTTERY_DEBUG: Parsing post ##{@post.id}. Raw params extracted: #{params.inspect}")

    required_keys = [:name, :prize, :winner_count, :draw_type, :draw_condition]
    if required_keys.any? { |key| params[key].blank? }
      Rails.logger.warn("LOTTERY_DEBUG: One or more required params are missing or blank. Aborting lottery creation.")
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
      lottery_params[:draw_at] = Time.zone.parse(params[:draw_condition]) rescue nil
      unless lottery_params[:draw_at]
        Rails.logger.warn("LOTTERY_DEBUG: Invalid date format for draw_condition: '#{params[:draw_condition]}'. Aborting.")
        return
      end
    else # by_reply
      lottery_params[:draw_reply_count] = params[:draw_condition]&.to_i
    end

    Lottery.create!(lottery_params)
    add_tag("抽奖中")
    Rails.logger.warn("LOTTERY_DEBUG: Successfully created lottery for topic ##{@topic.id}")
  end

  private

  def parse_raw(raw)
    params = {}
    params[:name] = raw[/\[lottery-name\](.*?)\[\/lottery-name\]/m, 1]&.strip
    params[:prize] = raw[/\[lottery-prize\](.*?)\[\/lottery-prize\]/m, 1]&.strip
    params[:winner_count] = raw[/\[lottery-winners\](.*?)\[\/lottery-winners\]/m, 1]&.to_i
    
    draw_type_str = raw[/\[lottery-draw-type\](.*?)\[\/lottery-draw-type\]/m, 1]&.strip
    params[:draw_condition] = raw[/\[lottery-condition\](.*?)\[\/lottery-condition\]/m, 1]&.strip
    
    if draw_type_str == "时间开奖"
      params[:draw_type] = Lottery::DRAW_TYPES[:by_time]
    elsif draw_type_str == "回复数开奖"
      params[:draw_type] = Lottery::DRAW_TYPES[:by_reply]
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
