import sys
import os
from pathlib import Path
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, 
    QHBoxLayout, QLabel, QLineEdit, QSpinBox, QPushButton,
    QFileDialog, QDoubleSpinBox, QFormLayout, QMessageBox
)
from PySide6.QtCore import Qt


class RimeConfigApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Rime 配置")
        self.setMinimumWidth(500)
        
        # 配置文件路径
        self.config_path = Path.home() / "rime_cfg.txt"
        
        # 当前offset值
        self.current_offset = 0
        
        # 初始化UI
        self.init_ui()
        
        # 加载配置
        self.load_config()
    
    def init_ui(self):
        """初始化用户界面"""
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        
        layout = QVBoxLayout(central_widget)
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)
        
        # 创建表单布局
        form_layout = QFormLayout()
        form_layout.setSpacing(10)
        
        # 1. 速率设置
        self.rate_spinbox = QSpinBox()
        self.rate_spinbox.setMinimum(1)
        self.rate_spinbox.setMaximum(1000)
        self.rate_spinbox.setValue(1)
        form_layout.addRow("速率:", self.rate_spinbox)
        
        # 2. 文件位置设置
        file_layout = QHBoxLayout()
        self.file_path_edit = QLineEdit()
        self.file_path_edit.setPlaceholderText("请选择txt文件路径")
        
        browse_button = QPushButton("浏览...")
        browse_button.clicked.connect(self.browse_file)
        
        file_layout.addWidget(self.file_path_edit)
        file_layout.addWidget(browse_button)
        form_layout.addRow("文件位置:", file_layout)
        
        # 3. 百分比设置
        self.percentage_spinbox = QDoubleSpinBox()
        self.percentage_spinbox.setMinimum(0.0)
        self.percentage_spinbox.setMaximum(100.0)
        self.percentage_spinbox.setValue(0.0)
        self.percentage_spinbox.setDecimals(2)
        self.percentage_spinbox.setSuffix("%")
        self.percentage_spinbox.setSingleStep(0.1)
        form_layout.addRow("百分比:", self.percentage_spinbox)
        
        layout.addLayout(form_layout)
        
        # 确定按钮
        button_layout = QHBoxLayout()
        button_layout.addStretch()
        
        save_button = QPushButton("确定")
        save_button.setMinimumWidth(100)
        save_button.clicked.connect(self.save_config)
        button_layout.addWidget(save_button)
        
        layout.addLayout(button_layout)
        
        # 添加一些间距
        layout.addStretch()
        
        # 配置文件信息
        config_info_label = QLabel(f"配置文件: {self.config_path}")
        config_info_label.setStyleSheet("color: gray; font-size: 10px;")
        layout.addWidget(config_info_label)
    
    def browse_file(self):
        """浏览并选择txt文件"""
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择txt文件",
            str(Path.home()),
            "Text Files (*.txt);;All Files (*.*)"
        )
        
        if file_path:
            self.file_path_edit.setText(file_path)
    
    def load_config(self):
        """从配置文件加载配置"""
        if not self.config_path.exists():
            # 创建默认配置
            self.create_default_config()
        
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            if len(lines) >= 3:
                offset = int(lines[0].strip())
                file_path = lines[1].strip()
                rate = int(lines[2].strip())
                
                # 保存offset
                self.current_offset = offset
                
                # 设置界面值
                self.rate_spinbox.setValue(rate)
                self.file_path_edit.setText(file_path)
                
                # 计算并设置百分比
                percentage = self.calculate_percentage(offset, file_path)
                self.percentage_spinbox.setValue(percentage)
        
        except Exception as e:
            print(f"加载配置失败: {e}")
            self.create_default_config()
    
    def create_default_config(self):
        """创建默认配置文件"""
        try:
            with open(self.config_path, 'w', encoding='utf-8') as f:
                f.write("0\n")
                f.write("C:\\a.txt\n")
                f.write("1\n")
            
            # 设置默认值
            self.current_offset = 0
            self.rate_spinbox.setValue(1)
            self.file_path_edit.setText("C:\\a.txt")
            self.percentage_spinbox.setValue(0.0)
        
        except Exception as e:
            print(f"创建默认配置失败: {e}")
    
    def calculate_percentage(self, offset, file_path):
        """根据offset和文件路径计算百分比"""
        try:
            if os.path.exists(file_path):
                file_size = os.path.getsize(file_path)
                if file_size > 0:
                    return (offset / file_size) * 100
            return 0.0
        except Exception as e:
            print(f"计算百分比失败: {e}")
            return 0.0
    
    def calculate_offset(self, percentage, file_path):
        """根据百分比和文件路径计算offset"""
        try:
            if os.path.exists(file_path):
                file_size = os.path.getsize(file_path)
                return int((percentage / 100) * file_size)
            return 0
        except Exception as e:
            print(f"计算offset失败: {e}")
            return 0
    
    def save_config(self):
        """保存配置到文件"""
        try:
            # 获取当前设置
            file_path = self.file_path_edit.text()
            rate = self.rate_spinbox.value()
            percentage = self.percentage_spinbox.value()
            
            # 根据百分比计算offset
            offset = self.calculate_offset(percentage, file_path)
            self.current_offset = offset
            
            # 写入配置文件
            with open(self.config_path, 'w', encoding='utf-8') as f:
                f.write(f"{offset}\n")
                f.write(f"{file_path}\n")
                f.write(f"{rate}\n")
            
            print(f"配置已保存: offset={offset}, 百分比={percentage:.2f}%, 速率={rate}")
            
            # 显示成功提示框
            QMessageBox.information(
                self,
                "保存成功",
                "保存成功,请重新部署"
            )
        
        except Exception as e:
            print(f"保存配置失败: {e}")
            QMessageBox.warning(
                self,
                "保存失败",
                f"保存配置失败: {e}"
            )


def main():
    app = QApplication(sys.argv)
    
    window = RimeConfigApp()
    window.show()
    
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
