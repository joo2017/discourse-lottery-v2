# name: discourse-lottery-v2
# about: A modern, automated lottery plugin for Discourse based on time.
# version: 3.0.0
# authors: Your Name (Revised by AI)
# url: null

enabled_site_setting :lottery_v2_enabled

register_asset "stylesheets/common/lottery.scss"

after_initialize do
  # 加载Discourse核心依赖
  require_dependency 'topic_changer'
  
  # 加载插件自身的模型
  require_dependency File.expand_path('../app/models/lottery.rb', __FILE__)
  
  # 为Topic模型添加关联
  Topic.class_eval do
    has_one :lottery, class_name: "Lottery", dependent: :destroy
  end

  # 加载插件的所有服务和任务
  [
    '../app/services/lottery_creator.rb',
    '../app/services/lottery_manager.rb',
    '../jobs/scheduled/check_lotteries.rb',
    '../jobs/regular/create_lottery_from_topic.rb'
  ].each { |path| require_dependency File.expand_path(path, __FILE__) }
  
  # 监听主题创建事件，用于触发抽奖创建流程
  on(:topic_created) do |topic, opts, user|
    if SiteSetting.lottery_v2_enabled
      trigger_categories_setting = SiteSetting.lottery_v2_trigger_categories
      trigger_categories = trigger_categories_setting.is_a?(String) ? trigger_categories_setting.split('|').map(&:to_i).reject(&:zero?) : []
      
      trigger_tags_setting = SiteSetting.lottery_v2_trigger_tags
      trigger_tags = trigger_tags_setting.is_a?(String) ? trigger_tags_setting.split('|').map(&:downcase).compact_blank : []

      category_match = trigger_categories.empty? || trigger_categories.include?(topic.category_id)
      
      topic_tags = topic.tags.map(&:name).map(&:downcase)
      tags_match = trigger_tags.empty? || !topic_tags.intersection(trigger_tags).empty?

      if category_match && tags_match
        Jobs.enqueue(:create_lottery_from_topic, topic_id: topic.id)
      end
    end
  end

  # 监听新回复事件，用于清除参与人数缓存
  on(:post_created) do |post, opts, user|
    topic = post.topic
    if topic&.lottery.present?
      lottery = topic.lottery
      if lottery.running?
        cache_key = "discourse_lottery_v2:participants:#{lottery.id}"
        Rails.cache.delete(cache_key)
      end
    end
  end

  # 扩展TopicViewSerializer，向前端注入抽奖数据
  require_dependency "topic_view_serializer"
  class ::TopicViewSerializer
    attributes :lottery_data

    def lottery_data
      lottery = object.topic.lottery
      return nil unless lottery

      lottery_json = lottery.as_json(
        only: [
          :id, :name, :prize, :winner_count, :draw_at,
          :specific_floors, :description, :extra_info,
          :min_participants_user
        ],
        methods: [:participating_user_count]
      )
      
      parsed_winner_data = begin
        JSON.parse(lottery.winner_data) if lottery.winner_data.is_a?(String) && lottery.winner_data.present?
      rescue JSON::ParserError
        nil
      end
      
      lottery_json[:winner_data] = parsed_winner_data || lottery.winner_data

      lottery_json.merge(
        status: lottery.status_name.to_s,
        draw_type: lottery.draw_type_name.to_s,
        insufficient_participants_action: lottery.insufficient_participants_action_name.to_s
      )
    end
    
    def include_lottery_data?
      object.topic.lottery.present?
    end
  end
end
