# name: discourse-lottery-v2
# about: A modern, automated lottery plugin for Discourse.
# version: 2.3.0
# authors: Your Name (Designed by AI)
# url: null

enabled_site_setting :lottery_v2_enabled

register_asset "stylesheets/common/lottery.scss"

after_initialize do
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
      # 修正：使用 reject(&:zero?) 过滤掉因 'abc'.to_i 产生的无效分类ID 0
      trigger_categories = SiteSetting.lottery_v2_trigger_categories.split('|').map(&:to_i).reject(&:zero?)
      trigger_tags = SiteSetting.lottery_v2_trigger_tags.split('|').map(&:downcase).compact_blank

      category_match = trigger_categories.empty? || trigger_categories.include?(topic.category_id)
      
      topic_tags = topic.tags.map(&:name).map(&:downcase)
      # 修正：如果标签设置不为空，则必须至少有一个标签匹配
      # 使用 `intersect?` (Ruby 2.6+) 更具可读性，功能等同于 !((a & b).empty?)
      tags_match = trigger_tags.empty? || trigger_tags.intersect?(topic_tags)

      if category_match && tags_match
        Jobs.enqueue(:create_lottery_from_topic, topic_id: topic.id)
      end
    end
  end

  require_dependency "topic_view_serializer"
  class ::TopicViewSerializer
    attributes :lottery_data

    def lottery_data
      # 使用 object.topic.lottery 而不是查询，这样可以利用预加载
      lottery = object.topic.lottery
      return nil unless lottery

      # 使用 to_h.slice 将模型转换为哈希，然后选择需要的键，更安全
      lottery_json = lottery.as_json(
        only: [
          :name, :prize, :winner_count, :draw_at,
          :draw_reply_count, :specific_floors, :description,
          :extra_info, :winner_data
        ],
        methods: [:participating_user_count]
      )

      # 合并手动处理的字段，确保 enum 值是字符串
      lottery_json.merge(
        status: lottery.status.to_s,
        draw_type: lottery.draw_type.to_s
      )
    end
    
    def include_lottery_data?
      # 确保关联关系存在且已加载
      object.topic.association(:lottery).loaded? ? object.topic.lottery.present? : Lottery.exists?(topic_id: object.topic.id)
    end
  end
end
