class LotteryCreator
  def initialize(topic)
    @topic = topic
    @post = topic.first_post
    @user = topic.user
  end

  def create_from_template
    return log_and_return("Lottery already exists", :info) if Lottery.exists?(topic_id: @topic.id)
    
    allowed_levels_setting = SiteSetting.lottery_v2_allowed_trust_levels
    allowed_levels = allowed_levels_setting.is_a?(String) ? allowed_levels_setting.split('|').map(&:to_i) : []
    unless allowed_levels.include?(@user.trust_level)
      return log_and_return("User trust level #{@user.trust_level} not allowed", :warn)
    end
    
    begin
      raw = @post.raw
      params = parse_raw(raw)
      
      validation_result = validate_params(params, raw)
      return log_and_return(validation_result[:error], :warn) unless validation_result[:valid]

      lottery = create_lottery_record(params, validation_result[:draw_condition])
      
      if lottery&.persisted?
        add_tag("抽奖中")
        log_lottery_created(lottery)
      end
    rescue => e
      Rails.logger.error("LOTTERY_CREATE_ERROR: Topic ##{@topic.id} - #{e.class.name}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end
  end

  private

  def parse_raw(raw)
    params = {}
    pattern = /### (.+?)\n(.*?)(?=\n### |\z)/m
    raw.scan(pattern).each do |match|
      key = match[0].strip
      value = match[1].strip
      case key
      when "抽奖名称" then params[:name] = value
      when "活动奖品" then params[:prize] = value
      when "获奖人数" then params[:winner_count] = value.to_i
      when "开奖方式" then params[:draw_type] = value == "时间开奖" ? :by_time : (value == "回复数开奖" ? :by_reply : nil)
      when "指定中奖楼层 (可选)" then params[:specific_floors] = value
      when "简单说明 (可选)" then params[:description] = value
      when "其他说明 (可选)" then params[:extra_info] = value
      end
    end
    params
  end

  def validate_params(params, raw)
    required_keys = [:name, :prize, :winner_count, :draw_type]
    missing_keys = required_keys.select { |key| params[key].blank? }
    return { valid: false, error: "Missing required fields: #{missing_keys.join(', ')}" } if missing_keys.any?

    if params[:winner_count] <= 0 || params[:winner_count] > SiteSetting.lottery_v2_max_winners
      return { valid: false, error: "Invalid winner count: #{params[:winner_count]}. Must be between 1 and #{SiteSetting.lottery_v2_max_winners}." }
    end

    condition_str = raw[/### 开奖条件\n(.*?)(?=\n### |\z)/m, 1]&.strip
    parsed_condition = parse_draw_condition(condition_str, params[:draw_type])
    
    return { valid: false, error: "Invalid draw condition: #{condition_str}" } if parsed_condition.nil?

    { valid: true, draw_condition: parsed_condition }
  end

  def parse_draw_condition(condition_str, draw_type)
    return nil if condition_str.blank?
    case draw_type
    when :by_time then parse_time_condition(condition_str)
    when :by_reply then parse_reply_condition(condition_str)
    end
  end

  def parse_time_condition(condition)
    formats = ['%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M', '%Y/%m/%d %H:%M', '%m-%d %H:%M', '%m/%d %H:%M']
    max_future_date = Time.current.advance(days: SiteSetting.lottery_v2_max_future_days)
    
    formats.each do |format|
      begin
        parsed_time = DateTime.strptime(condition.strip, format).in_time_zone
        if !format.include?('%Y') && parsed_time < Time.current
          parsed_time = parsed_time.change(year: Time.current.year)
        end
        return parsed_time if parsed_time > Time.current && parsed_time <= max_future_date
      rescue ArgumentError
        next
      end
    end
    nil
  end

  def parse_reply_condition(condition)
    reply_count = condition.to_i
    reply_count > 0 ? reply_count : nil
  end

  def create_lottery_record(params, draw_condition)
    lottery_params = {
      topic_id: @topic.id, post_id: @post.id, created_by_id: @user.id,
      name: params[:name], prize: params[:prize], winner_count: params[:winner_count],
      draw_type: params[:draw_type], specific_floors: params[:specific_floors],
      description: params[:description], extra_info: params[:extra_info], status: :running
    }
    lottery_params[:draw_at] = draw_condition if params[:draw_type] == :by_time
    lottery_params[:draw_reply_count] = draw_condition if params[:draw_type] == :by_reply
    
    Lottery.transaction do
      lottery = Lottery.create!(lottery_params)
      create_audit_log(lottery, 'created')
      lottery
    end
  rescue ActiveRecord::RecordInvalid => e
    log_and_return("Validation failed: #{e.message}", :error)
    nil
  end
  
  def add_tag(tag_name)
    DiscourseTagging.tag_topic_by_names(@topic, Guardian.new(Discourse.system_user), [tag_name])
  end

  def log_lottery_created(lottery)
    condition = lottery.draw_at || lottery.draw_reply_count
    Rails.logger.info("LOTTERY_CREATED: ID=#{lottery.id}, Topic=#{@topic.id}, Type=#{lottery.draw_type}, Condition=#{condition}")
  end
  
  def log_and_return(message, level)
    Rails.logger.send(level, "LOTTERY_CREATE: Topic ##{@topic.id} - #{message}")
    nil
  end

  def create_audit_log(lottery, action)
    Rails.logger.info("LOTTERY_AUDIT: lottery_id=#{lottery.id}, action=#{action}, user_id=#{@user.id}, topic_id=#{@topic.id}")
  end
end
