import Component from "@glimmer/component";
import { inject as service } from "@ember/service";
import I18n from "I18n";

export default class LotteryCard extends Component {
  @service site;

  get lotteryData() {
    return this.args.outletArgs.model.topic.lottery_data;
  }

  get isRunning() {
    // 使用字符串进行比较
    return this.lotteryData.status === "running";
  }

  get isFinished() {
    // 使用字符串进行比较
    return this.lotteryData.status === "finished";
  }

  get drawConditionText() {
    // 使用字符串进行比较
    if (this.lotteryData.draw_type === "by_time" && this.lotteryData.draw_at) {
      const date = new Date(this.lotteryData.draw_at);
      return I18n.t("lottery_v2.draw_condition.by_time", { time: date.toLocaleString() });
    } else if (this.lotteryData.draw_type === "by_reply") {
      return I18n.t("lottery_v2.draw_condition.by_reply", { count: this.lotteryData.draw_reply_count });
    }
    return "";
  }
}
