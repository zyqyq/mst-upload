<template>
  <div class="containerBox" :class="{loading: loading}">
    <div id="chartBox" ref="chart" v-show="flag"></div>
    <div v-if="!flag" class="empty-tip">暂无数据，请先选择查询条件</div>
    <div v-if="loading" class="loading-mask">加载中...</div>
  </div>
</template>

<script>
import * as echarts from "echarts";
export default {
  name: "WindSpeedChartL2",
  data() {
    return {
      loading: false, // 遮罩层
      flag: null,
      chartData: []
    };
  },
  props: {
    filepath: {
      type: String,
      default: ''
    }
  },
  computed: {
    mode() {
      if (!this.filepath) return '';
      const m = this.filepath.match(/_([MS]T)(?:_processed)?\.TXT$/i);
      if (m) return m[1];
      const m2 = this.filepath.match(/_([MS]T)_processed\.TXT$/i);
      if (m2) return m2[1];
      return '';
    },
    setTime() {
      if (!this.filepath) return '';
      const m = this.filepath.match(/30M_(\d{14})_V/);
      if (m) {
        return m[1].replace(/(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/, '$1-$2-$3 $4:$5:$6');
      }
      return '';
    },
    processed() {
      if (!this.filepath) return '原始';
      return /_processed\.TXT$/i.test(this.filepath) ? '处理后' : '原始';
    }
  },
  methods: {
    async fetchData() {
      if (!this.filepath) {
        alert('未指定文件路径');
        return;
      }
      this.loading = true;
      try {
        const response = await fetch(this.filepath);
        const text = await response.text();
        const lines = text.split('\n').slice(33); // 跳过前33行
        const parsedData = lines.map(line => {
          const parts = line.split(/\s+/).filter(Boolean);
          if (parts.length < 15) return null;
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
        this.chartData = parsedData;
        this.flag = parsedData.length > 0;
        this.$nextTick(() => {
          this.makeChart();
        });
      } catch (error) {
        alert('文件读取失败');
        this.flag = false;
      } finally {
        this.loading = false;
      }
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
      const beam6Data = this.mode === "ST" ? heights_ST : heights_M;
      const processData = (beamData) => {
        const heightIndexMap = new Map();
        beamData.forEach((item, index) => {
          heightIndexMap.set(item[1], index);
        });
        const result = [];
        beam6Data.forEach(item => {
          if (heightIndexMap.has(item[1])) {
            result.push(beamData[heightIndexMap.get(item[1])]);
          } else {
            result.push([null, item[1]]);
          }
        });
        return result;
      };
      const defaultSeriesConfig = {
        type: "line",
        symbol: "circle",
        connectNulls: true,
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
      const option = {
        title: {
          text: this.setTime + " " + this.processed + " " + "各向风速图",
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
          min: this.mode === "ST" ? -7 : -10,
          max: this.mode === "ST" ? 7 : 10,
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
          min: 0,
          max: this.mode === "ST" ? 49 : 84,
          axisLabel: {
            interval: 2,
          },
        },
        tooltip: {
          trigger: "axis",
          show: true,
        },
        legend: {
          show: true,
          position: "top",
          top: 17,
          labels: {
            fontStyle: "normal",
            fontSize: 8,
            fontColor: "#333",
          },
          data: ["经向风速", "纬向风速", "垂直风速"],
        },
        grid: {
          left: "2%",
          bottom: "2%",
          containLabel: true,
        },
        series: [
          {
            name: "Beam",
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
            showSymbol: false,
            silent: true,
          },
          {
            name: "经向风速",
            data: processData(this.chartData.map((item) => [ (item.rv1 + item.rv2) / 2 / Math.sin(Math.PI / 12), item.height])),
            ...defaultSeriesConfig,
          },
          {
            name: "纬向风速",
            data: processData(this.chartData.map((item) => [ (item.rv3 + item.rv4) / 2 / Math.sin(Math.PI / 12), item.height])),
            ...defaultSeriesConfig,
          },
          {
            name: "垂直风速",
            data: processData(this.chartData.map((item) => [item.rv5, item.height])),
            ...defaultSeriesConfig,
          },
        ],
      };
      const chartBox = this.$refs.chart;
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
  height: calc(100vh - 20px);
  padding-top: 20px;
  position: relative;
  #chartBox {
    width: 100%;
    height: 100%;
  }
  .empty-tip {
    color: #999;
    font-size: 18px;
    margin: 40px auto;
    text-align: center;
  }
  .native-btn {
    padding: 8px 20px;
    font-size: 16px;
    cursor: pointer;
    background: #409eff;
    color: #fff;
    border: none;
    border-radius: 4px;
    transition: background 0.2s;
  }
  .native-btn:hover {
    background: #66b1ff;
  }
  .loading-mask {
    position: absolute;
    left: 0; right: 0; top: 0; bottom: 0;
    background: rgba(255,255,255,0.7);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 22px;
    color: #409eff;
    z-index: 10;
  }
}
</style>
