import os
import re
import sys
import json
import glob
import time
import argparse
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed


class Worker:
    """后台处理类（无 GUI 依赖）"""

    def __init__(self, d3dx_path, directory):
        self.d3dx_user_ini_path = d3dx_path
        self.batch_directory = directory
        self.success_details = []          # 存储 (file_path, changes) 的列表
        self.d3dx_cache = None
        self.d3dx_params_cache = {}

    def log(self, msg):
        """直接打印日志到控制台"""
        print(msg)

    def progress(self, value):
        """可选：打印进度（这里简单打印当前处理数）"""
        # 可自行决定是否打印进度，暂不实现以免刷屏
        pass

    def run(self):
        try:
            self.success_details = []
            self.log("开始处理...")

            if not self.preload_d3dx_data():
                return

            self.build_params_index()

            ini_files = self.find_ini_files(self.batch_directory)
            self.log(f"找到 {len(ini_files)} 个 INI 文件")

            if not ini_files:
                self.log("错误：未找到任何 INI 文件")
                return

            total = len(ini_files)
            processed = 0
            start_time = time.time()

            max_workers = min(4, total)
            batch_size = 10
            batches = [ini_files[i:i + batch_size] for i in range(0, total, batch_size)]

            for batch in batches:
                with ThreadPoolExecutor(max_workers=max_workers) as executor:
                    future_to_file = {
                        executor.submit(self.process_single_file, file_path): file_path
                        for file_path in batch
                    }
                    for future in as_completed(future_to_file):
                        file_path = future_to_file[future]
                        try:
                            result, message, changes = future.result()
                            if result:
                                self.success_details.append((file_path, changes))
                                self.log(f"✓ {os.path.basename(file_path)}: {message}")
                            else:
                                self.log(f"✗ {os.path.basename(file_path)}: {message}")
                        except Exception as e:
                            self.log(f"! {os.path.basename(file_path)}: 处理异常: {str(e)}")
                        processed += 1
                        # 打印进度百分比（可选）
                        # self.progress(int(processed / total * 100))

                self.log(f"进度: {processed}/{total}")

            total_time = time.time() - start_time
            self.log(f"处理完成！成功更新 {len(self.success_details)} 个文件，总计 {total} 个文件")
            self.log(f"总耗时 {total_time:.2f} 秒，平均每个文件 {total_time / total:.3f} 秒")

            self.display_success_details()
            self.save_log_to_file()

        except Exception as e:
            self.log(f"错误: {str(e)}")
            import traceback
            self.log(traceback.format_exc())
        finally:
            self.d3dx_cache = None
            self.d3dx_params_cache.clear()

    def preload_d3dx_data(self):
        if not self.d3dx_user_ini_path:
            return False
        try:
            start = time.time()
            with open(self.d3dx_user_ini_path, 'r', encoding='utf-8') as f:
                self.d3dx_cache = f.readlines()
            self.log(f"预加载 d3dx 文件成功，共 {len(self.d3dx_cache)} 行，耗时 {time.time() - start:.3f} 秒")
            return True
        except Exception as e:
            self.log(f"加载 d3dx 文件失败: {str(e)}")
            return False

    def build_params_index(self):
        if not self.d3dx_cache:
            return
        start = time.time()
        self.d3dx_params_cache.clear()
        for line in self.d3dx_cache:
            line_strip = line.strip()
            if '=' in line_strip:
                parts = line_strip.split('=', 1)
                param_path = parts[0].strip()
                param_value = parts[1].strip()
                path_parts = param_path.split('\\')
                if len(path_parts) >= 2:
                    key = '\\'.join(path_parts[-2:]).lower()
                    if key not in self.d3dx_params_cache:
                        self.d3dx_params_cache[key] = []
                    self.d3dx_params_cache[key].append((param_path, param_value))
        self.log(f"参数索引构建完成，共 {len(self.d3dx_params_cache)} 个键，耗时 {time.time() - start:.3f} 秒")

    def extract_params_from_d3dx(self, search_keyword):
        params = {}
        search_lower = search_keyword.lower()
        path_parts = search_lower.split('\\')
        if len(path_parts) >= 2:
            index_key = '\\'.join(path_parts[-2:])
            if index_key in self.d3dx_params_cache:
                for param_path, param_value in self.d3dx_params_cache[index_key]:
                    if search_lower in param_path.lower():
                        param_name = param_path.split('\\')[-1]
                        params[param_name.lower()] = (param_name, param_value)
        if not params:
            relevant_lines = [line for line in self.d3dx_cache
                              if search_lower in line.lower() and '=' in line]
            for line in relevant_lines:
                line_strip = line.strip()
                parts = line_strip.split('=', 1)
                param_path = parts[0].strip()
                param_name = param_path.split('\\')[-1]
                param_value = parts[1].strip()
                params[param_name.lower()] = (param_name, param_value)
        return params

    def get_search_keyword(self, file_path):
        dir_path = os.path.dirname(file_path)
        parent_dir = os.path.dirname(dir_path)
        grandparent_dir = os.path.basename(parent_dir)
        parent_dir_name = os.path.basename(dir_path)
        file_name = os.path.basename(file_path)
        return f"{grandparent_dir}\\{parent_dir_name}\\{file_name}"

    def find_matching_param(self, mod_param_name, d3dx_params):
        mod_param_lower = mod_param_name.lower()
        if mod_param_lower in d3dx_params:
            return d3dx_params[mod_param_lower]
        for d3dx_key, value in d3dx_params.items():
            if d3dx_key in mod_param_lower or mod_param_lower in d3dx_key:
                return value
        return None

    def update_mod_config(self, mod_lines, d3dx_params):
        """更新配置，返回 (新行列表, 更新计数, 变更详情列表)"""
        updated_count = 0
        new_lines = []
        changes = []  # 每个元素: (参数名, 旧值, 新值)
        in_constants = False

        for line in mod_lines:
            stripped = line.strip()
            orig_line = line

            if stripped.startswith('[') and stripped.endswith(']'):
                section = stripped[1:-1].strip()
                if section == 'Constants':
                    in_constants = True
                else:
                    in_constants = False
                new_lines.append(line)
                continue

            if not in_constants or '$' not in stripped:
                new_lines.append(line)
                continue

            param_match = re.search(r'\$(\w+)', stripped)
            if not param_match:
                new_lines.append(line)
                continue

            mod_param = param_match.group(1)
            match_result = self.find_matching_param(mod_param, d3dx_params)
            if not match_result:
                new_lines.append(line)
                continue

            d3dx_name, new_val = match_result

            pattern = r'\$' + re.escape(mod_param) + r'\b'
            m = re.search(pattern, line)
            if not m:
                new_lines.append(line)
                continue

            start, end = m.span()
            prefix = line[:end]          # 包含 $ 和参数名
            suffix = line[end:]           # 参数名后的所有内容

            # 提取旧值（如果有）和注释
            old_val = None
            comment = ''
            if '=' in suffix:
                eq_pos = suffix.index('=')
                after_eq = suffix[eq_pos + 1:]
                val_end = after_eq.find(';')
                if val_end != -1:
                    val_str = after_eq[:val_end].strip()
                    comment = after_eq[val_end:]
                else:
                    val_str = after_eq.strip()
                    comment = ''
                old_val = val_str
            else:
                if ';' in suffix:
                    semi_pos = suffix.index(';')
                    comment = suffix[semi_pos:]
                else:
                    comment = suffix

            # 构建新行
            new_line = prefix + " = " + str(new_val) + comment
            if orig_line.endswith('\n') and not new_line.endswith('\n'):
                new_line += '\n'

            if new_line != orig_line:
                updated_count += 1
                changes.append((mod_param, old_val if old_val is not None else '(无)', new_val))

            new_lines.append(new_line)

        return new_lines, updated_count, changes

    def process_single_file(self, file_path):
        try:
            namespace = None
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    mod_lines = f.readlines()
                for line in mod_lines:
                    if line.strip().startswith('namespace') and '=' in line:
                        namespace = line.split('=', 1)[1].strip()
                        break
            except Exception as e:
                return False, f"文件读取错误: {str(e)}", []

            if namespace:
                search_keyword = namespace
            else:
                search_keyword = self.get_search_keyword(file_path)

            d3dx_params = self.extract_params_from_d3dx(search_keyword)
            if not d3dx_params:
                return False, f"未找到匹配参数 - {search_keyword}", []

            new_lines, updated_count, changes = self.update_mod_config(mod_lines, d3dx_params)

            if updated_count > 0:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.writelines(new_lines)
                return True, f"成功更新 {updated_count} 个参数", changes
            else:
                return False, "无需更新参数", []

        except Exception as e:
            return False, f"处理失败: {str(e)}", []

    def find_ini_files(self, directory):
        ini_files = []
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file.lower().endswith('.ini'):
                    ini_files.append(os.path.join(root, file))
        return ini_files

    def display_success_details(self):
        if not self.success_details:
            self.log("没有成功更新的文件")
            return

        self.log(f"成功更新文件详情（共 {len(self.success_details)} 个）:")
        self.log("=" * 80)
        for file_path, changes in self.success_details:
            rel = os.path.relpath(file_path, self.batch_directory)
            self.log(f"[{rel}]")
            for param, old_val, new_val in changes:
                self.log(f"  参数: {param}  {old_val}  --->  {new_val}")
            self.log("-" * 60)
        self.log("=" * 80)

    def save_log_to_file(self):
        if not self.success_details:
            return

        log_pattern = "日志_*.log"
        log_files = glob.glob(log_pattern)

        old_content = ""
        if log_files:
            old_file = log_files[0]
            try:
                with open(old_file, 'r', encoding='utf-8') as f:
                    old_content = f.read()
                os.remove(old_file)
            except Exception as e:
                self.log(f"读取旧日志失败: {str(e)}")

        now = datetime.now()
        timestamp = now.strftime("%Y_%m_%d_%H_%M")
        new_filename = f"日志_{timestamp}.log"

        new_entry = f"\n--- {now.strftime('%Y-%m-%d %H:%M:%S')} ---\n"
        new_entry += f"处理目录: {self.batch_directory}\n"
        new_entry += f"成功更新文件详情（共 {len(self.success_details)} 个）:\n"
        for file_path, changes in self.success_details:
            rel = os.path.relpath(file_path, self.batch_directory)
            new_entry += f"[{rel}]\n"
            for param, old_val, new_val in changes:
                new_entry += f"  参数: {param}  {old_val}  --->  {new_val}\n"
            new_entry += "\n"
        new_entry += "-" * 60 + "\n"

        final_content = old_content + new_entry

        try:
            with open(new_filename, 'w', encoding='utf-8') as f:
                f.write(final_content)
            self.log(f"日志已保存至: {new_filename}")
        except Exception as e:
            self.log(f"保存日志失败: {str(e)}")


def find_d3dx_user_ini():
    """从当前目录查找 d3dx_user.ini"""
    base = os.path.dirname(os.path.abspath(sys.argv[0]))
    ini_path = os.path.join(base, "d3dx_user.ini")
    if os.path.isfile(ini_path):
        return ini_path
    return None


def main():
    parser = argparse.ArgumentParser(description="批量更新 MOD 预设参数（从 d3dx_user.ini 同步）")
    parser.add_argument("-d", "--d3dx", help="d3dx_user.ini 文件路径（默认在当前目录查找）")
    parser.add_argument("-p", "--path", required=True, help="待处理的 MOD 文件夹路径")
    args = parser.parse_args()

    d3dx_path = args.d3dx if args.d3dx else find_d3dx_user_ini()
    if not d3dx_path:
        print("错误：未找到 d3dx_user.ini，请使用 -d 参数指定路径")
        sys.exit(1)

    if not os.path.isfile(d3dx_path):
        print(f"错误：d3dx_user.ini 文件不存在 - {d3dx_path}")
        sys.exit(1)

    target_dir = args.path
    if not os.path.isdir(target_dir):
        print(f"错误：目标文件夹不存在 - {target_dir}")
        sys.exit(1)

    worker = Worker(d3dx_path, target_dir)
    worker.run()


if __name__ == "__main__":
    main()