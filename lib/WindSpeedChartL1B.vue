<template>
  <div v-loading="loading" class="containerBox">
    <div id="chartBox" ref="chart" v-show="flag"></div>
    <el-empty
      description="暂无数据，请先选择查询条件"
      style="margin: auto"
      v-show="!flag"
    ></el-empty>
  </div>
</template>

<script>
import { mstRadarData } from "@/api/smos/mstradar";
//import echarts from "echarts";
import * as echarts from "echarts5";
export default {
  name: "WindSpeedChartL1B",
  data() {
    return {
      loading: false, // 遮罩层
      flag: null,
      chartData: [],
    };
  },
  props: {
    mode: String,
    processed: String,
    setTime: String,
  },
 
  computed: {
    defaultPlatformId() {
      return this.$store.state.tailingsPond.value;
    },
  },
  methods: {
    // 查询L1B数据
    getChartList() {
      if (this.mode && this.setTime) {
        let params = {
          startTime: this.setTime,
          endTime: this.setTime,
          platformId: this.defaultPlatformId,
        };
        let choice = {
          type: "L1B",
          mode: this.mode,
          processed: this.processed,
        };
        this.loading = true;
        mstRadarData(params, choice)
          .then((response) => {
            this.loading = false;
            if (response.rows.length > 0) {
              this.flag = true;
              this.chartData = response.rows;
              //数据过滤
              this.chartData.forEach((item) => {
                item.rv1 = item.rv1 === -9999999 ? null : item.rv1;
                item.rv2 = item.rv2 === -9999999 ? null : item.rv2;
                item.rv3 = item.rv3 === -9999999 ? null : item.rv3;
                item.rv4 = item.rv4 === -9999999 ? null : item.rv4;
                item.rv5 = item.rv5 === -9999999 ? null : item.rv5;
              });
              const newData = [
                {
                  height: 50700,
                  rv1: null,
                  rv2: "-",
                  rv3: "-",
                  rv4: "-",
                  rv5: "-",
                },
                {
                  height: 51900,
                  rv1: null,
                  rv2: "-",
                  rv3: "-",
                  rv4: "-",
                  rv5: "-",
                },
                {
                  height: 49500,
                  rv1: null,
                  rv2: "-",
                  rv3: "-",
                  rv4: "-",
                  rv5: "-",
                },
                {
                  height: 48300,
                  rv1: null,
                  rv2: "-",
                  rv3: "-",
                  rv4: "-",
                  rv5: "-",
                },
                {
                  height: 47100,
                  rv1: null,
                  rv2: "-",
                  rv3: "-",
                  rv4: "-",
                  rv5: "-",
                },
                {
                  height: 45900,
                  rv1: null,
                  rv2: "-",
                  rv3: "-",
                  rv4: "-",
                  rv5: "-",
                },
              ];
              this.chartData.push(...newData);
              this.$nextTick(() => {
                this.makeChart();
              });
            } else {
              this.flag = false;
            }
          })
          .catch((error) => {
            this.loading = false;
            this.flag = false;
            console.error('Fetch data error:', error);
            this.$message.error('数据获取失败，请稍后重试');
          });
      } else {
        this.flag = false;
        this.$message.error("请选择查询条件");
      }
    },
    clear() {
      var myChart = echarts.init(document.getElementById("chartBox"));
      myChart.dispose();
    },
    makeChart() {
      const heights_ST_raw = [
        900.0, 1500.0, 2100.0, 2700.0, 3300.0, 3900.0, 4500.0, 5100.0, 5700.0,
        6300.0, 6900.0, 7500.0, 8100.0, 8700.0, 9300.0, 9900.0, 10500.0,
        11100.0, 11700.0, 12300.0, 12900.0, 13500.0, 14100.0, 14700.0, 15300.0,
        15900.0, 16500.0, 17100.0, 17700.0, 18300.0, 18900.0, 19500.0, 20100.0,
        20700.0, 21300.0, 21900.0, 22500.0, 23100.0, 23700.0, 24300.0, 24900.0,
        25500.0, 26100.0, 26700.0, 27300.0, 27900.0, 28500.0, 29100.0, 29700.0,
        30300.0,
      ];
      const heights_ST = heights_ST_raw.map((height) => [0, height]);
      const heights_M_raw = [
        300, 1500, 2700, 3900, 5100, 6300, 7500, 8700, 9900, 11100, 12300,
        13500, 14700, 15900, 17100, 18300, 19500, 20700, 21900, 23100, 24300,
        25500, 26700, 27900, 29100, 30300, 31500, 32700, 33900, 35100, 36300,
        37500, 38700, 39900, 41100, 42300, 43500, 44700, 45900, 47100, 48300,
        49500, 50700, 51900, 53100, 54300, 55500, 56700, 57900, 59100, 60300,
        61500, 62700, 63900, 65100, 66300, 67500, 68700, 69900, 71100, 72300,
        73500, 74700, 75900, 77100, 78300, 79500, 80700, 81900, 83100, 84300,
        85500, 86700, 87900, 89100, 90300, 91500, 92700, 93900, 95100, 96300,
        97500, 98700, 99900, 101100,
      ];
      const heights_M = heights_M_raw.map((height) => [0, height]);
      const defaultSeriesConfig = {
        //通用配置
        type: "line",
        symbol: "circle",
        connectNulls: false,
        smooth: true,
        symbolSize: 7,
        lineStyle: {
          width: 3,
          shadowColor: "rgba(0,0,0,0.3)",
          shadowBlur: 5,
          shadowOffsetY: 8,
        },
        emphasis: {
          focus: "series",
          blurScope: "coordinateSystem",
        },
      };

        // 获取 Beam 6 的数据
      const beam6Data = this.mode === "ST" ? heights_ST : heights_M;

      // 处理其他 Beam 的数据
      const processData = (beamData) => {
        // 创建一个映射来存储 beamData 中的高度到其索引的关系
        const heightIndexMap = new Map();
        beamData.forEach((item, index) => {
          heightIndexMap.set(item[1], index);
        });

        // 创建一个新数组来保存处理后的结果
        const result = [];

        // 遍历 beamData6
        beam6Data.forEach(item => {
          // 检查高度是否在 beamData 中存在
          if (heightIndexMap.has(item[1])) {
            // 如果存在，则直接添加该项
            result.push(beamData[heightIndexMap.get(item[1])]);
          } else {
            // 如果不存在，则添加 [null, 高度]
            result.push([null, item[1]]);
          }
        });

        // 返回处理后的结果数组
        return result;
      };

      const option = {
        title: {
          text: this.setTime + " " + this.processed + " " + "L1B数据折线图",
          left: "center",
          top: 0,
          textStyle: {
            fontSize: 15,
            fontWeight: "bold",
          },
        },
        xAxis: {
          type: "value",
          name: "Radial Velocity (m/s)",
          min: this.mode === "ST" ? -10 : -40,
          max: this.mode === "ST" ? 10 : 40,
          nameLocation: "middle",
          axisLine: {
            show: true,
          },
          axisLabels: {
            show: true,
          },
        },
        yAxis: {
          type: "category",
          name: "Height (m)",
          top: 30,
          max: this.mode === "ST" ? 49 : 84,
          axisLabel: {
            interval: 2,
          },
        },
        grid: {
          left: "2%",
          bottom: "2%",
          containLabel: true,
        },
        tooltip: {
          trigger: "axis",
          show: true,
        },
        legend: {
          show: true, // 显示图例
          position: "top", // 图例的位置
          top: 17, // 图例距离顶部的距离
          labels: {
            // 图例标签的样式
            fontStyle: "normal",
            fontSize: 8,
            fontColor: "#333",
          },
          data: ["Beam 1", "Beam 2", "Beam 3", "Beam 4", "Beam 5"],
        },
        series: [
          {
            name: "Beam 6",
            type: "line",
            data: beam6Data,
            lineStyle: {
              opacity: 0,
            },
            itemStyle: {
              color: "transparent",
              borderColor: "transparent",
            },
            tooltip: {
              show: false,
            },
            showSymbol: false, // 禁止显示数据点符号
            silent: true, // 禁止所有交互
          },
          {
            name: "Beam 1",
            data: processData(this.chartData.map((item) => [item.rv1, item.height])),
            ...defaultSeriesConfig,
          },
          {
            name: "Beam 2",
            data:  processData(this.chartData.map((item) => [item.rv2, item.height])),
            ...defaultSeriesConfig,
          },
          {
            name: "Beam 3",
            data:  processData(this.chartData.map((item) => [item.rv3, item.height])),
            ...defaultSeriesConfig,
          },
          {
            name: "Beam 4",
            data:  processData(this.chartData.map((item) => [item.rv4, item.height])),
            ...defaultSeriesConfig,
          },
          {
            name: "Beam 5",
            data:  processData(this.chartData.map((item) => [item.rv5, item.height])),
            ...defaultSeriesConfig,
          },
        ],
      };
      const chartBox = this.$refs.chart; //id多处使用会重复，ref在组件内是唯一的
      echarts.dispose(chartBox);
      const myChart = echarts.init(chartBox);

      myChart.clear();
      myChart.setOption(option);
    },

  },
};
</script>

<style scoped lang="scss">
.containerBox {
  width: 100%;
  border-radius: 3px;
  background-color: #f5f7fa;
  height: calc(100vh - 250px);
  padding-top: 20px;

  #chartBox {
    width: 100%;
    height: 100%;
  }
}
</style>
 const fetchData = async () => {
        const response = await fetch(props.filepath);
        const text = await response.text();
  
        const lines = text.split('\n').slice(33);
        const parsedData = lines.map(line => {
          const parts = line.split(/\s+/).filter(Boolean);
          if (parts.length < 11) return null;
          return {
            height: parseFloat(parts[0]),
            rv1: parseFloat(parts[2]),
            rv2: parseFloat(parts[5]),
            rv3: parseFloat(parts[8]),
            rv4: parseFloat(parts[11]),
            rv5: parseFloat(parts[14]),
          };
        }).filter(Boolean);
  
        parsedData.forEach(item => {
          item.rv1 = item.rv1 === -9999999 ? null : item.rv1;
          item.rv2 = item.rv2 === -9999999 ? null : item.rv2;
          item.rv3 = item.rv3 === -9999999 ? null : item.rv3;
          item.rv4 = item.rv4 === -9999999 ? null : item.rv4;
          item.rv5 = item.rv5 === -9999999 ? null : item.rv5;
        });
        //console.log(text);
        data.value = parsedData;
      };
  