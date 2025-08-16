class LotteryCreator
  def initialize(topic)
    @topic = topic
    @post = topic.first_post
    @user = topic.user
  end

  def create_from_template
    return log_and_return("抽奖已存在", :info) if Lottery.exists?(topic_id: @topic.id)
    
    begin
      raw = @post.raw
      params = parse_raw(raw)
      
      validation_result = validate_params(params)
      return log_and_return(validation_result[:error], :warn) unless validation_result[:valid]

      lottery = create_lottery_record(params)
      
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
      when "获奖人数" then params[:winner_count] = value
      when "指定中奖楼层" then params[:specific_floors] = value
      when "开奖时间" then params[:draw_at_str] = value
      when "最低参与人数" then params[:min_participants_user] = value
      when "开奖时人数不足的处理方式" then params[:insufficient_action_str] = value
      when "简单说明" then params[:description] = value
      end
    end
    params
  end

  def validate_params(params)
    required_keys = %i[name prize draw_at_str min_participants_user insufficient_action_str]
    missing_keys = required_keys.select { |key| params[key].blank? }
    return { valid: false, error: "缺少必填字段: #{missing_keys.join(', ')}" } if missing_keys.any?

    is_specific_floor = params[:specific_floors].present?
    if is_specific_floor
      if params[:specific_floors].split(/[,，\s]+/).map(&:to_i).any? { |f| f <= 1 }
        return { valid: false, error: "指定楼层必须大于1" }
      end
    elsif params[:winner_count].blank? || params[:winner_count].to_i <= 0
      return { valid: false, error: "随机抽奖时，获奖人数必须填写且大于0" }
    end

    if params[:winner_count].to_i > SiteSetting.lottery_v2_max_winners
      return { valid: false, error: "获奖人数不能超过管理员设置的最大值 (#{SiteSetting.lottery_v2_max_winners})" }
    end
    
    admin_min_participants = SiteSetting.lottery_v2_min_participants_admin
    if params[:min_participants_user].to_i < admin_min_participants
      return { valid: false, error: "最低参与人数不能低于管理员设置的底线 (#{admin_min_participants})" }
    end

    if Time.zone.parse(params[:draw_at_str]).nil?
      return { valid: false, error: "开奖时间格式无效" }
    end

    { valid: true }
  end

  def create_lottery_record(params)
    draw_type = params[:specific_floors].present? ? :specific_floor : :random
    
    winner_count = if draw_type == :specific_floor
                     params[:specific_floors].split(/[,，\s]+/).map(&:strip).uniq.count
                   else
                     params[:winner_count].to_i
                   end
    
    insufficient_action = params[:insufficient_action_str] == "继续开奖" ? :draw_anyway : :cancel

    lottery_params = {
      topic_id: @topic.id, post_id: @post.id, created_by_id: @user.id,
      name: params[:name], prize: params[:prize],
      winner_count: winner_count,
      draw_type: Lottery::DRAW_TYPES[draw_type],
      draw_at: Time.zone.parse(params[:draw_at_str]),
      specific_floors: params[:specific_floors],
      description: params[:description],
      min_participants_user: params[:min_participants_user].to_i,
      insufficient_participants_action: Lottery::INSUFFICIENT_PARTICIPANTS_ACTIONS[insufficient_action],
      status: Lottery::STATUSES[:running]
    }
    
    lottery = Lottery.create!(lottery_params)
    create_audit_log(lottery, 'created')
    lottery
  end
  
  def add_tag(tag_name)
    DiscourseTagging.tag_topic_by_names(@topic, Guardian.new(Discourse.system_user), [tag_name])
  end

  def log_lottery_created(lottery)
    Rails.logger.info("LOTTERY_CREATED: ID=#{lottery.id}, Topic=#{@topic.id}, Type=#{lottery.draw_type_name}, DrawAt=#{lottery.draw_at}")
  end
  
  def log_and_return(message, level)
    Rails.logger.send(level, "LOTTERY_CREATE: Topic ##{@topic.id} - #{message}")
    nil
  end

  def create_audit_log(lottery, action)
    Rails.logger.info("LOTTERY_AUDIT: lottery_id=#{lottery.id}, action=#{action}, user_id=#{@user.id}")
  end
end
