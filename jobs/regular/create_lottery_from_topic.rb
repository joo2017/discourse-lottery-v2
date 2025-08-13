module Jobs
  class CreateLotteryFromTopic < ::Jobs::Base
    def execute(args)
      topic = Topic.find_by(id: args[:topic_id])
      return unless topic
      LotteryCreator.new(topic).create_from_template
    end
  end
end
