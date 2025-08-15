class LotteryCreator
  def initialize(topic)
    @topic = topic
    @post = topic.first_post
    @user = topic.user
  end

  def create_from_template
    # 幂等性检查，防止因任务重试等原因重复创建
    return if Lottery.exists?(topic_id: @topic.id)
    
    raw = @post.raw
    params = parse_raw(raw)
    
    # 基础必填项校验
    required_keys = [:name, :prize, :winner_count, :draw_type]
    if required_keys.any? { |key| params[key].blank? }
      Rails.logger.warn("LOTTERY_CREATE_ABORTED: Missing required fields for topic ##{@topic.id}.")
      return
    end

    if params[:winner_count].to_i <= 0
      Rails.logger.warn("LOTTERY_CREATE_ABORTED: Winner count must be positive for topic ##{@topic.id}.")
      return
    end

    draw_condition = raw[/### 开奖条件\n(.*?)(?=\n### |\z)/m, 1]&.strip
    if draw_condition.blank?
      Rails.logger.warn("LOTTERY_CREATE_ABORTED: Draw condition is blank for topic ##{@topic.id}.")
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
      status: :running
    }

    # 根据开奖类型，进行特定校验
    if params[:draw_type] == :by_time
      begin
        parsed_time = Time.zone.parse(draw_condition)
        # 校验时间是否有效且在未来
        if parsed_time.nil? || parsed_time <= Time.zone.now
          Rails.logger.warn("LOTTERY_CREATE_ABORTED: Invalid or past draw time '#{draw_condition}' for topic ##{@topic.id}.")
          return
        end
        lottery_params[:draw_at] = parsed_time
      rescue ArgumentError
        Rails.logger.warn("LOTTERY_CREATE_ABORTED: Could not parse draw time '#{draw_condition}' for topic ##{@topic.id}.")
        return
      end
    elsif params[:draw_type] == :by_reply
      draw_reply_count = draw_condition.to_i
      # 校验回复数是否为正数
      if draw_reply_count <= 0
        Rails.logger.warn("LOTTERY_CREATE_ABORTED: Draw reply count must be positive for topic ##{@topic.id}.")
        return
      end
      lottery_params[:draw_reply_count] = draw_reply_count
    end

    if Lottery.create(lottery_params)
      add_tag("抽奖中")
    end
  end

  private

  def parse_raw(raw)
    params = {}
    # 修正：使用更具弹性的正则表达式，匹配到下一个 '###' 或字符串结尾
    # 这可以防止因用户在表单中多输入一个换行符而导致的解析失败
    pattern = /### (.+?)\n(.*?)(?=\n### |\z)/m

    raw.scan(pattern).each do |match|
      key = match[0].strip
      value = match[1].strip
      
      case key
      when "抽奖名称"
        params[:name] = value
      when "活动奖品"
        params[:prize] = value
      when "获奖人数"
        params[:winner_count] = value.to_i
      when "开奖方式"
        params[:draw_type] = value == "时间开奖" ? :by_time : (value == "回复数开奖" ? :by_reply : nil)
      when "指定中奖楼层 (可选)"
        params[:specific_floors] = value
      when "简单说明 (可选)"
        params[:description] = value
      when "其他说明 (可选)"
        params[:extra_info] = value
      end
    end
    
    params
  end

  def add_tag(tag_name)
    # 后台任务中修改主题的最佳实践是使用 system_user 的 Guardian
    guardian = Guardian.new(Discourse.system_user)
    DiscourseTagging.tag_topic_by_names(@topic, guardian, [tag_name])
  end
end
