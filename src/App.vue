<template>
  <div id="app">
    <div class="main-flex">
      <div class="flex-item">
        <WindSpeedChartL1B 
          ref="l1bRef"
          :filepath="filepath"
        />
      </div>
      <div class="flex-item">
        <WindSpeedChartL2 
          ref="l2Ref"
          :filepath="filepath"
        />
      </div>
    </div>
  </div>
</template>

<script>
import WindSpeedChartL1B from './components/WindSpeedChartL1B.vue'
import WindSpeedChartL2 from './components/WindSpeedChartL2.vue'

export default {
  name: 'App',
  components: {
    WindSpeedChartL1B,
    WindSpeedChartL2
  },
  data() {
    return {
      filepath: ''
    }
  },
  methods: {
    setFilepath(path) {
      this.filepath = path;
      this.$nextTick(() => {
        this.$refs.l1bRef && this.$refs.l1bRef.fetchData();
        this.$refs.l2Ref && this.$refs.l2Ref.fetchData();
      });
    }
  },
  mounted() {
    // 可选：如果需要页面加载时自动渲染，可在此处设置默认路径
    // this.setFilepath('/OQZQB_MSTR01_PSPP_L1B_30M_20240801110000_V01.00_M.TXT');
    window.app = {
      setFilepath: this.setFilepath
    };
  }
}
</script>

<style>
#app {
  font-family: Avenir, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  text-align: center;
  color: #2c3e50;
  margin: 0;
  padding: 0;
  background: transparent !important;
  min-height: 100vh;
  height: 100vh;
}
html, body {
  height: 100%;
  margin: 0;
  padding: 0;
  background: transparent !important;
}
.main-flex {
  display: flex;
  flex-direction: row;
  justify-content: stretch;
  align-items: stretch;
  width: 100vw;
  height: 100vh;
}
.flex-item {
  flex: 1 1 0;
  min-width: 0;
  min-height: 0;
  height: 100%;
  display: flex;
  flex-direction: column;
  background: transparent;
}
</style>
