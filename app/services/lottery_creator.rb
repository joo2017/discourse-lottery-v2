class LotteryCreator
  def initialize(topic)
    @topic = topic
    @post = topic.first_post
    @user = topic.user
  end

  def create_from_template
    raw = @post.raw
    params = parse_raw(raw)

    return if params.empty?

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
      extra_info: params[:extra_info],
      status: :running
    )

    add_tag("抽奖中")
  end

  private

  def parse_raw(raw)
    params = {}
    params[:name] = raw.match(/\[lottery-name\](.*?)\[\/lottery-name\]/m)&.captures&.first&.strip
    params[:prize] = raw.match(/\[lottery-prize\](.*?)\[\/lottery-prize\]/m)&.captures&.first&.strip
    params[:winner_count] = raw.match(/\[lottery-winners\](.*?)\[\/lottery-winners\]/m)&.captures&.first&.to_i
    
    draw_type_str = raw.match(/\[lottery-draw-type\](.*?)\[\/lottery-draw-type\]/m)&.captures&.first&.strip
    if draw_type_str == "时间开奖"
      params[:draw_type] = :by_time
      draw_at_str = raw.match(/\[lottery-condition\](.*?)\[\/lottery-condition\]/m)&.captures&.first&.strip
      params[:draw_at] = Time.zone.parse(draw_at_str) rescue nil
    elsif draw_type_str == "回复数开奖"
      params[:draw_type] = :by_reply
      params[:draw_reply_count] = raw.match(/\[lottery-condition\](.*?)\[\/lottery-condition\]/m)&.captures&.first&.to_i
    end

    params[:specific_floors] = raw.match(/\[lottery-floors\](.*?)\[\/lottery-floors\]/m)&.captures&.first&.strip
    params[:description] = raw.match(/\[lottery-description\](.*?)\[\/lottery-description\]/m)&.captures&.first&.strip
    params[:extra_info] = raw.match(/\[lottery-extra\](.*?)\[\/lottery-extra\]/m)&.captures&.first&.strip

    params.compact # Remove nil values
  end

  def add_tag(tag_name)
    tag = Tag.find_or_create_by(name: tag_name)
    @topic.tags << tag unless @topic.tags.include?(tag)
    @topic.save!
  end
end
