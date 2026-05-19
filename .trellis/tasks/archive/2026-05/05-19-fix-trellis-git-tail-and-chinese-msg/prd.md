# 修复 Trellis git 收尾并统一中文提交说明

## 目标

- 修复 `task.py archive` 后旧任务目录删除未被同次提交捕获的问题。
- 修复 `.trellis/workspace/` 被顶层 `.gitignore` 忽略，导致 `add_session.py` 无法自动提交 journal 的问题。
- 记录一条协作约定：后续给用户的 git 提交/上传说明尽量使用中文。

## 验收标准

- 归档任务后，`git status` 不再残留已归档任务源目录的 `D` 项。
- `.trellis/workspace/yuyu/index.md` 和 `journal-1.md` 可以被正常跟踪。
- 相关规范已更新，后续同类问题可复用。
