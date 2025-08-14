# /var/discourse/plugins/discourse-lottery-v2/plugin.rb (已修正语法错误)

# name: discourse-lottery-v2
# about: A modern, automated lottery plugin for Discourse.
# version: 2.2.1
# authors: Your Name (Designed by AI)
# url: null

enabled_site_setting :lottery_v2_enabled

register_asset "stylesheets/common/lottery.scss"

after_initialize do
  [
    '../app/models/lottery.rb',
    '../app/services/lottery_creator.rb',
    '../app/services/lottery_manager.rb',
    '../jobs/scheduled/check_lotteries.rb',
    '../jobs/regular/create_lottery_from_topic.rb'
  ].each { |path| require_dependency File.expand_path(path, __FILE__) }

  on(:topic_created) do |topic, opts, user|
    if SiteSetting.lottery_v2_enabled
      trigger_categories = SiteSetting.lottery_v2_trigger_categories.split('|').map(&:to_i).compact
      trigger_tags = SiteSetting.lottery_v2_trigger_tags.split('|').map(&:downcase).compact_blank

      category_match = trigger_categories.empty? || trigger_categories.include?(topic.category_id)
      tags_match = trigger_tags.empty? || !((topic.tags.map(&:name).map(&:downcase) & trigger_tags).empty?)

      # --- 这就是之前被截断的、导致错误的一行代码 ---
      if category_match && tags_match
        Jobs.enqueue(:create_lottery_from_topic, topic_id: topic.id)
      end # 这个 end 对应上面的 if
    end # 这个 end 对应 if SiteSetting.lottery_v2_enabled
  end # 这个 end 对应 on(:topic_created)

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
    object.topic&.lottery.present?
  end

  Topic.class_eval { has_one :lottery, class_name: "Lottery", dependent: :destroy }
end
