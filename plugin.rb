# name: discourse-lottery-v2
# about: A modern, automated lottery plugin for Discourse.
# version: 2.2.0
# authors: Your Name (Designed by AI)
# url: null

enabled_site_setting :lottery_v2_enabled

register_asset "stylesheets/common/lottery.scss"

module ::LotteryV2
  PLUGIN_NAME = "discourse-lottery-v2".freeze
end

after_initialize do
  # 加载所有依赖文件
  [
    '../app/models/lottery.rb',
    '../app/services/lottery_creator.rb',
    '../app/services/lottery_manager.rb',
    '../jobs/scheduled/check_lotteries.rb',
    '../jobs/regular/create_lottery_from_topic.rb',
    '../app/controllers/admin/lottery_admin_controller.rb',
    '../config/routes.rb'
  ].each { |path| require_dependency File.expand_path(path, __FILE__) }

  # 事件驱动：当新主题创建时
  on(:topic_created) do |topic, opts, user|
    if SiteSetting.lottery_v2_enabled
      trigger_categories = SiteSetting.lottery_v2_trigger_categories.split('|').map(&:to_i)
      trigger_tags = SiteSetting.lottery_v2_trigger_tags.split('|').map(&:downcase)
      
      category_match = trigger_categories.empty? || trigger_categories.include?(topic.category_id)
      tags_match = trigger_tags.empty? || !((topic.tags.map(&:name).map(&:downcase) & trigger_tags).empty?)

      if category_match && tags_match
        Jobs.enqueue(:create_lottery_from_topic, topic_id: topic.id)
      end
    end
  end

  # 将抽奖数据附加到主题
  add_to_serializer(:topic_view, :lottery_data, false) do
    Lottery.find_by(topic_id: object.topic.id)&.as_json(
      only: [
        :name, :prize, :winner_count, :draw_type, :draw_at,
        :draw_reply_count, :specific_floors, :description,
        :extra_info, :status, :winner_data
      ],
      methods: [:participating_user_count]
    )
  end

  add_to_serializer(:topic_view, :include_lottery_data?) do
    Lottery.exists?(topic_id: object.topic.id)
  end
end
