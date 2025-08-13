# name: discourse-lottery-v2
# about: A modern, automated lottery plugin for Discourse.
# version: 2.2.2
# authors: Your Name (Designed by AI)
# url: null

enabled_site_setting :lottery_v2_enabled

register_asset "stylesheets/common/lottery.scss"

after_initialize do
  # --- START: 最终的、绝对正确的修复 ---
  
  # 将所有依赖加载放在 after_initialize 块的顶部
  require_dependency File.expand_path('../app/models/lottery.rb', __FILE__)
  require_dependency File.expand_path('../app/services/lottery_creator.rb', __FILE__)
  require_dependency File.expand_path('../app/services/lottery_manager.rb', __FILE__)
  require_dependency File.expand_path('../jobs/scheduled/check_lotteries.rb', __FILE__)
  require_dependency File.expand_path('../jobs/regular/create_lottery_from_topic.rb', __FILE__)
  require_dependency File.expand_path('../app/controllers/admin/lottery_admin_controller.rb', __FILE__)
  
  # 将 Topic 的关联关系也放在这里
  Topic.class_eval do
    has_one :lottery, class_name: "Lottery", dependent: :destroy
  end

  # 事件处理器
  DiscourseEvent.on(:topic_created) do |topic, opts, user|
    if SiteSetting.lottery_v2_enabled
      # 为了调试，我们先在日志中打印信息
      Rails.logger.warn "LOTTERY_DEBUG: Topic created event triggered for topic ID #{topic.id}"
      
      trigger_categories = SiteSetting.lottery_v2_trigger_categories.split('|').map(&:to_i).compact
      trigger_tags = SiteSetting.lottery_v2_trigger_tags.split('|').map(&:downcase).compact_blank

      category_match = trigger_categories.empty? || trigger_categories.include?(topic.category_id)
      tags_match = trigger_tags.empty? || !((topic.tags.map(&:name).map(&:downcase) & trigger_tags).empty?)
      
      Rails.logger.warn "LOTTERY_DEBUG: Category match: #{category_match}, Tags match: #{tags_match}"

      if category_match && tags_match
        Rails.logger.warn "LOTTERY_DEBUG: Conditions met. Enqueuing job for topic ID #{topic.id}"
        Jobs.enqueue(:create_lottery_from_topic, topic_id: topic.id)
      end
    end
  end

  # 序列化器
  add_to_serializer(:topic_view, :lottery_data, false) do
    object.topic&.lottery&.as_json(
      only: [
        :name, :prize, :winner_count, :draw_type, :draw_at,
        :draw_reply_count, :specific_floors, :description,
        :extra_info, :status, :winner_data
      ],
      methods: [:participating_user_count]
    )
  end

  add_to_serializer(:topic_view, :include_lottery_data?) do
    object.topic&.lottery.present?
  end

  # --- END: 最终的、绝对正确的修复 ---
end
