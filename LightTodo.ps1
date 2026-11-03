Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class TodoWindow : Form {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x312 && m.WParam.ToInt32() == 1) {
            if (Visible && ContainsFocus) Hide();
            else { Show(); WindowState = FormWindowState.Normal; Activate(); }
        }
        base.WndProc(ref m);
    }
}
"@
$ErrorActionPreference = 'Stop'
$folder = Join-Path $env:LOCALAPPDATA 'LightTodo'
$path = Join-Path $folder 'data.json'
$state = @{tasks=@(); note=''; files=@(); shortcuts=@()}
if (Test-Path -LiteralPath $path) {
    $loaded = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $state = @{tasks=@($loaded.tasks | Where-Object { $_ }); note=[string]$loaded.note; files=@($loaded.files | Where-Object { $_ }); shortcuts=@($loaded.shortcuts | Where-Object { $_ })}
}
function Save-State {
    try {
        [IO.Directory]::CreateDirectory($folder) | Out-Null
        [IO.File]::WriteAllText($path, ($state | ConvertTo-Json -Depth 6))
    } catch { [Windows.Forms.MessageBox]::Show("保存失败：$($_.Exception.Message)") | Out-Null }
}
$mutex = New-Object Threading.Mutex($false,'Local\LightTodo')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); return }
$form = New-Object TodoWindow
$form.Text = 'To do list'
$form.ClientSize = '418,514'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI',10)
$cream = [Drawing.ColorTranslator]::FromHtml('#FAF7ED')
$paper = [Drawing.ColorTranslator]::FromHtml('#FFFDF6')
$ink = [Drawing.ColorTranslator]::FromHtml('#302A20')
$muted = [Drawing.ColorTranslator]::FromHtml('#716453')
$gold = [Drawing.ColorTranslator]::FromHtml('#FFD665')
$green = [Drawing.ColorTranslator]::FromHtml('#CBE0C1')
$form.BackColor = $cream
$form.ForeColor = $ink
$line = [Drawing.ColorTranslator]::FromHtml('#DFD7C8')
$track = [Drawing.ColorTranslator]::FromHtml('#EFE9DC')
$form.Add_Paint({
    $g = $_.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $brush = New-Object Drawing.SolidBrush($track)
    $pen = New-Object Drawing.Pen($line)
    try {
        $g.FillRectangle($brush,16,94,386,39)
        $g.DrawRectangle($pen,18,139,380,332)
        $g.DrawLine($pen,19,477,398,477)
    } finally { $brush.Dispose(); $pen.Dispose() }
})
$pages = [ordered]@{}
function Add-Tab($title) {
    $page = New-Object Windows.Forms.Panel
    $page.SetBounds(20,141,376,328)
    $page.BackColor = $paper
    $page.Visible = $pages.Count -eq 0
    $pages.Add($title,$page)
    $form.Controls.Add($page)
    return $page
}
function Add-Control($parent,$type,$label,$x,$y,$w,$h) {
    $control = New-Object "Windows.Forms.$type"
    $control.Text = $label
    $control.SetBounds($x,$y,$w,$h)
    if ($control -is [Windows.Forms.Button]) {
        $control.FlatStyle = 'Flat'
        $control.FlatAppearance.BorderColor = $line
        $control.FlatAppearance.MouseDownBackColor = $gold
        $control.FlatAppearance.MouseOverBackColor = $green
        $control.BackColor = $cream
        $control.Cursor = [Windows.Forms.Cursors]::Hand
    } elseif ($control -is [Windows.Forms.TextBoxBase] -or $control -is [Windows.Forms.ListBox]) {
        $control.BorderStyle = 'FixedSingle'
        $control.BackColor = $paper
    }
    $control.ForeColor = $ink
    $parent.Controls.Add($control)
    return $control
}
$heading = Add-Control $form Label 'To do list' 19 17 379 44
$heading.Font = New-Object Drawing.Font('Segoe UI',24,[Drawing.FontStyle]::Bold)
$heading.TextAlign = 'MiddleLeft'
$heading.BackColor = [Drawing.Color]::Transparent
$subtitle = Add-Control $form Label '随手记下，慢慢完成。' 20 62 378 23
$subtitle.TextAlign = 'MiddleLeft'
$subtitle.ForeColor = $muted
$tasks = Add-Tab '待办'
$inputBox = Add-Control $tasks TextBox '' 13 36 265 28
$add = Add-Control $tasks Button '添加' 286 33 76 32
$list = Add-Control $tasks ListBox '' 13 77 349 197
$add.BackColor = $gold
$null = Add-Control $tasks Label '接下来做什么？' 13 10 260 23
$contentFont = New-Object Drawing.Font('Microsoft YaHei UI',12)
$remarkFont = New-Object Drawing.Font('Microsoft YaHei UI',11)
$list.Font = $contentFont
$inputBox.Font = $contentFont
$list.DrawMode = 'OwnerDrawVariable'
$list.Add_MeasureItem({
    if ($_.Index -lt 0 -or $_.Index -ge $state.tasks.Count) { return }
    $note = [string]$state.tasks[$_.Index].note
    $_.ItemHeight = 32
    if ($note) {
        $size = [Windows.Forms.TextRenderer]::MeasureText($note,$remarkFont,[Drawing.Size]::new(292,0),[Windows.Forms.TextFormatFlags]::WordBreak)
        $_.ItemHeight += [Math]::Min(180,$size.Height + 5)
    }
})
$list.Add_DrawItem({
    if ($_.Index -lt 0 -or $_.Index -ge $state.tasks.Count) { return }
    $_.DrawBackground()
    $task = $state.tasks[$_.Index]
    $box = [Drawing.Rectangle]::new($_.Bounds.X+8,$_.Bounds.Y+9,14,14)
    $check = if ($task.done) { 'Checked' } else { 'Normal' }
    [Windows.Forms.ControlPaint]::DrawCheckBox($_.Graphics,$box,$check)
    $width = [Math]::Max(1,$_.Bounds.Width-36)
    $title = [Drawing.Rectangle]::new($_.Bounds.X+30,$_.Bounds.Y+4,$width,25)
    [Windows.Forms.TextRenderer]::DrawText($_.Graphics,$task.title,$contentFont,$title,$_.ForeColor,'EndEllipsis, SingleLine, NoPrefix')
    if ($task.note) {
        $remark = [Drawing.Rectangle]::new($title.X,$_.Bounds.Y+29,$width,$_.Bounds.Height-30)
        [Windows.Forms.TextRenderer]::DrawText($_.Graphics,$task.note,$remarkFont,$remark,$_.ForeColor,'WordBreak, EndEllipsis, NoPrefix')
    }
    $_.DrawFocusRectangle()
})
$taskNote = Add-Control $tasks Button '编辑备注' 13 284 100 31
$remove = Add-Control $tasks Button '删除选中' 121 284 100 31
function Refresh-Tasks {
    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        foreach ($task in $state.tasks) { $list.Items.Add($task.title) | Out-Null }
    } finally { $list.EndUpdate() }
}
Refresh-Tasks
$addTask = {
    $title = $inputBox.Text.Trim()
    if (!$title) { return }
    $state.tasks += [pscustomobject]@{title=$title; done=$false; note=''}
    Save-State
    Refresh-Tasks
    $inputBox.Clear()
    $inputBox.Focus()
}
$add.Add_Click($addTask)
$inputBox.Add_KeyDown({
    if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; & $addTask }
})
function Toggle-Task($index) {
    if ($index -lt 0) { return }
    $state.tasks[$index].done = -not $state.tasks[$index].done
    Save-State
    $list.Invalidate()
}
$list.Add_MouseClick({
    if ($_.Button -eq 'Left' -and $_.X -le 27) { Toggle-Task ($list.IndexFromPoint($_.Location)) }
})
$list.Add_KeyDown({
    if ($_.KeyCode -eq 'Space') {
        $_.SuppressKeyPress = $true
        Toggle-Task $list.SelectedIndex
    }
})
$remove.Add_Click({
    $index = $list.SelectedIndex
    if ($index -lt 0) { return }
    if ([Windows.Forms.MessageBox]::Show('删除选中的待办？','To do list','YesNo') -ne 'Yes') { return }
    $state.tasks = @(for ($i=0;$i -lt $state.tasks.Count;$i++) { if ($i -ne $index) { $state.tasks[$i] } })
    Save-State
    Refresh-Tasks
})
$taskNote.Add_Click({
    $index = $list.SelectedIndex
    if ($index -lt 0) { return }
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'To do list · 待办备注'
    $dialog.BackColor = $cream
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = '375,225'
    $dialog.Font = $form.Font
    $editor = Add-Control $dialog TextBox $state.tasks[$index].note 12 12 350 158
    $editor.Font = $contentFont
    $editor.Multiline = $true
    $editor.ScrollBars = 'Vertical'
    $ok = Add-Control $dialog Button '保存' 282 182 80 30
    $ok.BackColor = $gold
    $ok.DialogResult = 'OK'
    try {
        if ($dialog.ShowDialog($form) -eq 'OK') {
            $state.tasks[$index].note = $editor.Text
            Save-State
            Refresh-Tasks
            $list.SelectedIndex = $index
        }
    } finally { $dialog.Dispose() }
})
$notes = Add-Tab '速记'
$memo = Add-Control $notes TextBox $state.note 13 36 349 278
$null = Add-Control $notes Label '随手写 · 自动保存' 13 10 349 23
$memo.Font = $contentFont
$memo.Multiline = $true
$memo.ScrollBars = 'Vertical'
$memo.WordWrap = $true
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 400
$timer.Add_Tick({ $timer.Stop(); Save-State })
$memo.Add_TextChanged({ $state.note = $memo.Text; $timer.Stop(); $timer.Start() })
$shelf = Add-Tab '文件中转'
$null = Add-Control $shelf Label '拖入文件，再从列表拖到目标窗口。' 13 10 349 25
$files = Add-Control $shelf ListBox '' 13 40 349 234
$files.Font = $contentFont
$files.SelectionMode = 'MultiExtended'
$files.HorizontalScrollbar = $true
$files.AllowDrop = $true
$pick = Add-Control $shelf Button '添加文件' 13 284 100 31
$detach = Add-Control $shelf Button '移出列表' 121 284 100 31
function Refresh-Files {
    $files.Items.Clear()
    foreach ($file in $state.files) { $files.Items.Add($file) | Out-Null }
}
function Add-Files($paths) {
    foreach ($file in $paths) {
        if ((Test-Path -LiteralPath $file -PathType Leaf) -and $state.files -notcontains $file) { $state.files += $file }
    }
    Save-State
    Refresh-Files
}
Refresh-Files
$files.Add_DragEnter({
    if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' }
})
$files.Add_DragDrop({ Add-Files ($_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) })
$files.Add_MouseDown({ $script:dragOrigin = $_.Location; $script:dragReady = $_.Button -eq 'Left' -and $files.IndexFromPoint($_.Location) -ge 0 })
$files.Add_MouseMove({
    if (!$script:dragReady -or $_.Button -ne 'Left') { return }
    if ([Math]::Abs($_.X-$script:dragOrigin.X) -lt 5 -and [Math]::Abs($_.Y-$script:dragOrigin.Y) -lt 5) { return }
    $script:dragReady = $false
    [string[]]$selected = @($files.SelectedItems | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if (!$selected.Count) { return }
    $data = New-Object Windows.Forms.DataObject
    $data.SetData([Windows.Forms.DataFormats]::FileDrop,$selected)
    $files.DoDragDrop($data,'Copy') | Out-Null
})
$pick.Add_Click({
    $picker = New-Object Windows.Forms.OpenFileDialog
    $picker.Multiselect = $true
    try { if ($picker.ShowDialog($form) -eq 'OK') { Add-Files $picker.FileNames } }
    finally { $picker.Dispose() }
})
$detach.Add_Click({
    $selected = @($files.SelectedItems | ForEach-Object { $_ })
    $state.files = @($state.files | Where-Object { $selected -notcontains $_ })
    Save-State
    Refresh-Files
})
$navigation = [ordered]@{}
$x = 19
foreach ($name in $pages.Keys) {
    $button = Add-Control $form Button $name $x 98 118 31
    $button.FlatAppearance.BorderSize = 0
    $button.Tag = $name
    $button.Add_Click({
        param($sender,$eventArgs)
        foreach ($key in $pages.Keys) {
            $active = $key -eq $sender.Tag
            $pages[$key].Visible = $active
            $navigation[$key].BackColor = if ($active) { $gold } else { $track }
            $navigation[$key].AccessibleDescription = if ($active) { '当前页面' } else { '' }
        }
    })
    $button.BackColor = $track
    $navigation.Add($name,$button)
    $x += 130
}
$navigation['待办'].BackColor = $gold
$navigation['待办'].AccessibleDescription = '当前页面'
$pick.BackColor = $gold
$status = Add-Control $form Label 'Ctrl + Alt + Space  ·  唤起 / 隐藏' 19 482 380 24
$status.ForeColor = $muted
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Icon = [Drawing.SystemIcons]::Application
$tray.Text = 'To do list'
$tray.Visible = $true
$menu = New-Object Windows.Forms.ContextMenuStrip
$showItem = $menu.Items.Add('打开To do list')
$pinItem = $menu.Items.Add('保持置顶')
$pinItem.Checked = $true
$pinItem.CheckOnClick = $true
$exitItem = $menu.Items.Add('退出')
$tray.ContextMenuStrip = $menu
$showWindow = { $form.Show(); $form.Activate() }
$tray.Add_DoubleClick($showWindow)
$showItem.Add_Click($showWindow)
$pinItem.Add_CheckedChanged({ $form.TopMost = $pinItem.Checked })
$exitItem.Add_Click({ $script:exiting = $true; $form.Close() })
$form.Add_FormClosing({
    if ($_.CloseReason -eq 'UserClosing' -and !$script:exiting) { $_.Cancel = $true; $form.Hide() }
})
$handle = $form.Handle
$registered = [TodoWindow]::RegisterHotKey($handle,1,0x4003,0x20)
if (!$registered) { $status.Text = '快捷键已被占用，可双击托盘图标打开。' }
$form.Add_Shown({ $inputBox.Focus() })
try { [Windows.Forms.Application]::Run($form) }
finally {
    if ($timer.Enabled) { $timer.Stop(); Save-State }
    if ($registered) { [TodoWindow]::UnregisterHotKey($handle,1) | Out-Null }
    $timer.Dispose()
    $tray.Dispose()
    $menu.Dispose()
    $form.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}



