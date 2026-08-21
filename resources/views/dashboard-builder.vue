<template>
  <div class="dashboard-builder">
    <!-- Header -->
    <div class="builder-header">
      <h1>Dashboard Builder</h1>
      <div class="header-actions">
        <button @click="toggleEditMode" :class="{ active: editMode }" class="btn-edit">
          {{ editMode ? '✓ Done Editing' : '✎ Edit Dashboard' }}
        </button>
        <button @click="saveDashboard" class="btn-save" v-if="editMode">💾 Save</button>
        <button @click="resetToDefault" class="btn-reset" v-if="editMode">🔄 Reset</button>
        <button @click="exportDashboard" class="btn-export">⬇️ Export</button>
      </div>
    </div>

    <!-- Widget Palette (in edit mode) -->
    <div class="widget-palette" v-if="editMode">
      <h3>Available Widgets</h3>
      <div class="widget-list">
        <div
          v-for="widget in availableWidgets"
          :key="widget.id"
          class="widget-item"
          draggable="true"
          @dragstart="startDragWidget($event, widget)"
        >
          <span class="widget-icon">{{ widget.icon }}</span>
          <span class="widget-name">{{ widget.name }}</span>
        </div>
      </div>
    </div>

    <!-- Canvas -->
    <div
      class="dashboard-canvas"
      @drop="dropWidget"
      @dragover.prevent
      @dragenter.prevent
      :class="{ 'edit-mode': editMode }"
    >
      <!-- Grid of widgets -->
      <div class="widgets-container">
        <div
          v-for="(widget, index) in dashboardWidgets"
          :key="widget.id"
          class="widget-wrapper"
          :style="getWidgetStyle(widget)"
          @click="selectWidget(widget, index)"
          :class="{ selected: selectedWidget?.id === widget.id }"
        >
          <!-- Widget Header (edit mode) -->
          <div class="widget-header" v-if="editMode">
            <span class="widget-title">{{ widget.name }}</span>
            <button
              class="btn-remove"
              @click.stop="removeWidget(index)"
              title="Remove widget"
            >
              ✕
            </button>
          </div>

          <!-- Widget Content -->
          <div class="widget-content">
            <component
              :is="getWidgetComponent(widget.type)"
              :widget="widget"
              :mode="editMode ? 'edit' : 'view'"
            />
          </div>

          <!-- Resize Handle (edit mode) -->
          <div
            class="resize-handle"
            v-if="editMode"
            @mousedown="startResize($event, index)"
          >
            ⤡
          </div>
        </div>
      </div>

      <!-- Empty State -->
      <div class="empty-state" v-if="dashboardWidgets.length === 0">
        <p v-if="editMode">Drag widgets from the palette to build your dashboard</p>
        <p v-else>No widgets configured. Click "Edit Dashboard" to add widgets.</p>
      </div>
    </div>

    <!-- Widget Inspector (edit mode) -->
    <div class="widget-inspector" v-if="editMode && selectedWidget">
      <h3>{{ selectedWidget.name }} Settings</h3>
      <div class="inspector-fields">
        <!-- Refresh Rate -->
        <div class="field-group">
          <label>Refresh Rate (seconds)</label>
          <input
            v-model.number="selectedWidget.refreshRate"
            type="number"
            min="5"
            max="3600"
          />
        </div>

        <!-- Size -->
        <div class="field-group">
          <label>Size</label>
          <select v-model="selectedWidget.size">
            <option value="small">Small (1x1)</option>
            <option value="medium">Medium (2x2)</option>
            <option value="large">Large (3x3)</option>
            <option value="full">Full Width (4x2)</option>
          </select>
        </div>

        <!-- Data Source -->
        <div class="field-group">
          <label>Data Source</label>
          <input v-model="selectedWidget.dataSource" type="text" />
        </div>

        <!-- Chart Type (for analytics widgets) -->
        <div class="field-group" v-if="selectedWidget.type === 'analytics'">
          <label>Chart Type</label>
          <select v-model="selectedWidget.chartType">
            <option value="line">Line Chart</option>
            <option value="bar">Bar Chart</option>
            <option value="pie">Pie Chart</option>
            <option value="area">Area Chart</option>
          </select>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'DashboardBuilder',
  data() {
    return {
      editMode: false,
      dashboardWidgets: [],
      selectedWidget: null,
      resizingIndex: null,
      draggedWidget: null,

      // Available widget types
      availableWidgets: [
        { id: 'w1', type: 'kpi', name: 'KPI Card', icon: '📊' },
        { id: 'w2', type: 'chart', name: 'Line Chart', icon: '📈' },
        { id: 'w3', type: 'chart', name: 'Bar Chart', icon: '📊' },
        { id: 'w4', type: 'table', name: 'Data Table', icon: '📋' },
        { id: 'w5', type: 'map', name: 'Map View', icon: '🗺️' },
        { id: 'w6', type: 'timeline', name: 'Timeline', icon: '⏱️' },
        { id: 'w7', type: 'gauge', name: 'Gauge Chart', icon: '🎯' },
        { id: 'w8', type: 'analytics', name: 'Analytics', icon: '📈' },
        { id: 'w9', type: 'alerts', name: 'Alerts Log', icon: '🚨' },
        { id: 'w10', type: 'status', name: 'Status Panel', icon: '✓' },
        { id: 'w11', type: 'calendar', name: 'Calendar', icon: '📅' },
        { id: 'w12', type: 'metrics', name: 'Metrics', icon: '📐' }
      ]
    };
  },

  mounted() {
    this.loadDashboard();
  },

  methods: {
    toggleEditMode() {
      this.editMode = !this.editMode;
      this.selectedWidget = null;
    },

    startDragWidget(event, widget) {
      this.draggedWidget = { ...widget };
      event.dataTransfer.effectAllowed = 'copy';
    },

    dropWidget(event) {
      event.preventDefault();
      if (!this.editMode || !this.draggedWidget) return;

      const rect = event.currentTarget.getBoundingClientRect();
      const x = event.clientX - rect.left;
      const y = event.clientY - rect.top;

      const newWidget = {
        id: `widget-${Date.now()}`,
        ...this.draggedWidget,
        position: { x, y },
        size: 'medium',
        refreshRate: 60,
        chartType: 'line',
        dataSource: '/api/data/default'
      };

      this.dashboardWidgets.push(newWidget);
      this.draggedWidget = null;
    },

    removeWidget(index) {
      this.dashboardWidgets.splice(index, 1);
      this.selectedWidget = null;
    },

    selectWidget(widget, index) {
      if (this.editMode) {
        this.selectedWidget = { ...widget, _index: index };
      }
    },

    startResize(event, index) {
      this.resizingIndex = index;
      const startX = event.clientX;
      const startY = event.clientY;
      const widget = this.dashboardWidgets[index];
      const startSize = { ...widget.position };

      const onMouseMove = (e) => {
        const deltaX = e.clientX - startX;
        const deltaY = e.clientY - startY;
        widget.position.x = startSize.x + deltaX;
        widget.position.y = startSize.y + deltaY;
      };

      const onMouseUp = () => {
        document.removeEventListener('mousemove', onMouseMove);
        document.removeEventListener('mouseup', onMouseUp);
        this.resizingIndex = null;
      };

      document.addEventListener('mousemove', onMouseMove);
      document.addEventListener('mouseup', onMouseUp);
    },

    getWidgetStyle(widget) {
      return {
        left: `${widget.position?.x || 0}px`,
        top: `${widget.position?.y || 0}px`,
        width: this.getSizeWidth(widget.size),
        height: this.getSizeHeight(widget.size)
      };
    },

    getSizeWidth(size) {
      const widths = { small: '200px', medium: '350px', large: '500px', full: '100%' };
      return widths[size] || '350px';
    },

    getSizeHeight(size) {
      const heights = { small: '150px', medium: '250px', large: '400px', full: '250px' };
      return heights[size] || '250px';
    },

    getWidgetComponent(type) {
      const components = {
        kpi: 'WidgetKPI',
        chart: 'WidgetChart',
        table: 'WidgetTable',
        map: 'WidgetMap',
        timeline: 'WidgetTimeline',
        gauge: 'WidgetGauge',
        analytics: 'WidgetAnalytics',
        alerts: 'WidgetAlerts',
        status: 'WidgetStatus',
        calendar: 'WidgetCalendar',
        metrics: 'WidgetMetrics'
      };
      return components[type] || 'WidgetPlaceholder';
    },

    saveDashboard() {
      const payload = {
        name: 'My Custom Dashboard',
        widgets: this.dashboardWidgets,
        layout: 'grid',
        theme: 'light'
      };

      fetch('/api/dashboards', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
        .then((r) => r.json())
        .then((data) => {
          alert('Dashboard saved successfully!');
          this.editMode = false;
        })
        .catch((err) => alert('Error saving dashboard: ' + err.message));
    },

    loadDashboard() {
      fetch('/api/dashboards/current')
        .then((r) => r.json())
        .then((data) => {
          this.dashboardWidgets = data.widgets || [];
        })
        .catch(() => {
          // Use default dashboard if API fails
          this.dashboardWidgets = [];
        });
    },

    resetToDefault() {
      if (confirm('Reset dashboard to default?')) {
        this.dashboardWidgets = [];
        this.selectedWidget = null;
      }
    },

    exportDashboard() {
      const data = {
        name: 'Dashboard Export',
        widgets: this.dashboardWidgets,
        exportDate: new Date().toISOString()
      };
      const json = JSON.stringify(data, null, 2);
      const blob = new Blob([json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `dashboard-${Date.now()}.json`;
      a.click();
    }
  }
};
</script>

<style scoped>
.dashboard-builder {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: #f5f5f5;
  gap: 10px;
  padding: 10px;
}

.builder-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: white;
  padding: 15px;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.header-actions {
  display: flex;
  gap: 10px;
}

.btn-edit, .btn-save, .btn-reset, .btn-export {
  padding: 8px 16px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
}

.btn-edit {
  background: #2196F3;
  color: white;
}

.btn-edit.active {
  background: #FF9800;
}

.btn-save {
  background: #4CAF50;
  color: white;
}

.btn-reset {
  background: #F44336;
  color: white;
}

.btn-export {
  background: #9C27B0;
  color: white;
}

.widget-palette {
  background: white;
  padding: 15px;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.widget-list {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 10px;
  margin-top: 10px;
}

.widget-item {
  padding: 12px;
  background: #f9f9f9;
  border: 2px solid #ddd;
  border-radius: 4px;
  cursor: move;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  transition: all 0.3s;
}

.widget-item:hover {
  background: #e3f2fd;
  border-color: #2196F3;
}

.widget-icon {
  font-size: 24px;
}

.widget-name {
  font-size: 12px;
  text-align: center;
  font-weight: 500;
}

.dashboard-canvas {
  flex: 1;
  background: white;
  border-radius: 8px;
  padding: 20px;
  position: relative;
  overflow: auto;
  border: 2px dashed transparent;
  transition: all 0.3s;
}

.dashboard-canvas.edit-mode {
  border-color: #2196F3;
  background: #fafafa;
}

.widgets-container {
  position: relative;
  min-height: 400px;
}

.widget-wrapper {
  position: absolute;
  background: white;
  border: 1px solid #ddd;
  border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
  transition: all 0.3s;
  cursor: pointer;
}

.widget-wrapper.selected {
  border: 2px solid #2196F3;
  box-shadow: 0 2px 12px rgba(33, 150, 243, 0.4);
}

.widget-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px;
  border-bottom: 1px solid #eee;
  background: #f5f5f5;
}

.widget-title {
  font-weight: 600;
  font-size: 14px;
}

.btn-remove {
  background: none;
  border: none;
  color: #F44336;
  cursor: pointer;
  font-size: 16px;
  padding: 0;
}

.widget-content {
  padding: 15px;
  min-height: 100px;
}

.resize-handle {
  position: absolute;
  bottom: 5px;
  right: 5px;
  cursor: nwse-resize;
  color: #2196F3;
  font-size: 18px;
  opacity: 0.5;
  transition: opacity 0.3s;
}

.widget-wrapper:hover .resize-handle {
  opacity: 1;
}

.empty-state {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 300px;
  color: #999;
  font-size: 16px;
  text-align: center;
}

.widget-inspector {
  background: white;
  padding: 15px;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  max-width: 300px;
}

.inspector-fields {
  margin-top: 15px;
  display: flex;
  flex-direction: column;
  gap: 15px;
}

.field-group {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.field-group label {
  font-weight: 600;
  font-size: 13px;
  color: #333;
}

.field-group input,
.field-group select {
  padding: 8px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 13px;
}

@media (max-width: 1024px) {
  .dashboard-builder {
    flex-direction: column;
  }

  .widget-list {
    grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
  }

  .widget-inspector {
    max-width: 100%;
  }
}
</style>
