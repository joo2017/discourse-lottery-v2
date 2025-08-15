# name: discourse-lottery-v2
# about: A modern, automated lottery plugin for Discourse.
# version: 2.8.0
# authors: Your Name (Revised by AI)
# url: null

enabled_site_setting :lottery_v2_enabled

register_asset "stylesheets/common/lottery.scss"

after_initialize do
  # 【重要】最终修正：在插件初始化时，强制加载所有Discourse核心依赖
  require_dependency 'topic_changer'
  
  require_dependency File.expand_path('../app/models/lottery.rb', __FILE__)
  
  Topic.class_eval do
    has_one :lottery, class_name: "Lottery", dependent: :destroy
  end

  [
    '../app/services/lottery_creator.rb',
    '../app/services/lottery_manager.rb',
    '../jobs/scheduled/check_lotteries.rb',
    '../jobs/regular/create_lottery_from_topic.rb'
  ].each { |path| require_dependency File.expand_path(path, __FILE__) }
  
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

  require_dependency "topic_view_serializer"
  class ::TopicViewSerializer
    attributes :lottery_data

    def lottery_data
      lottery = object.topic.lottery
      return nil unless lottery

      lottery_json = lottery.as_json(
        only: [
          :id,
          :name, :prize, :winner_count, :draw_at,
          :draw_reply_count, :specific_floors, :description,
          :extra_info, :winner_data
        ],
        methods: [:participating_user_count]
      )

      lottery_json.merge(
        status: lottery.status_name.to_s,
        draw_type: lottery.draw_type_name.to_s
      )
    end
    
    def include_lottery_data?
      object.topic.lottery.present?
    end
  end
end
