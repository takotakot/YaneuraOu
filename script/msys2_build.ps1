﻿Param(
  [String[]]$Compiler,
  [String[]]$Edition,
  [String[]]$Target,
  [String[]]$Cpu,
  [String]$Extra
)
<#
# MSYS2をインストールしたディレクトリで（もしくはPATH環境変数を設定して）以下を実行:

msys2_shell.cmd -msys2 -defterm -no-start -lc 'pacman --needed --noconfirm -Syuu pactoys-git';
msys2_shell.cmd -msys2 -defterm -no-start -lc 'pacboy --needed --noconfirm -Syuu clang:m openblas:x openmp:x toolchain:m base-devel:';

# MSYS2パッケージの更新、更新出来る項目が無くなるまで繰り返し実行、場合によってはMSYS2の再起動が必要
#>
$TGOBJS = New-Object System.Collections.ArrayList;
$TGCPUS = @('ZEN1';);
$TGCOMPILERS = @('clang++';);
@(
  @{
    BUILDDIR = 'tanuki_MATE';
    EDITION = 'TANUKI_MATE_ENGINE';
    BUILDNAME = 'tanuki_MATE';
    TARGET = @('normal';'tournament';);
  };
)|
Where-Object{
  $_Edition = $_.EDITION;
  (-not $Edition) -or ($Edition|Where-Object{$_Edition -like $_});
}|
ForEach-Object{
  $_TgObj = $_;
  $_TgObj.TARGET|Where-Object{ $_Target = $_; (-not $Target) -or ($Target|Where-Object{$_Target -like $_}); }|ForEach-Object{ $_Target = $_;
  $TGCOMPILERS|Where-Object{ $_Compiler = $_; (-not $Compiler) -or ($Compiler|Where-Object{$_Compiler -like $_}); }|ForEach-Object{ $_Compiler = $_;
  $TGCPUS|Where-Object{ $_Cpu = $_; ((-not $Cpu) -or ($Cpu|Where-Object{$_Cpu -like $_})) -and ($_Cpu -ne 'NO_SSE' -or $_Target -ne 'evallearn'); }|ForEach-Object{ $_Cpu = $_;
    $TGOBJS.Add(@{
      Os = 'Windows_NT';
      Make = 'mingw32-make';
      Makefile = 'Makefile';
      Jobs = $env:NUMBER_OF_PROCESSORS;
      WorkDir = (Join-Path $PSScriptRoot ../source/);
      BuildDir = (Join-Path (Join-Path $PSScriptRoot ../build/windows/) $_TgObj.BUILDDIR);
      Edition = $_TgObj.EDITION;
      BuildName = $_TgObj.BUILDNAME;
      Target = $_Target;
      Compiler = $_Compiler;
      Cpu = $_Cpu;
      Extra = $Extra;
    })|Out-Null;
  }}};
};
function MakeExec($o) {
  Push-Location $o.WorkDir;
  # New-TemporaryFile にて一時作業用ディレクトリの場所を作成する。
  # New-TemporaryFile にて作成される一時ファイルの場所は、Windowsでは TMP 環境変数（それが無ければ TEMP 環境変数）の値が使われる。
  # https://docs.microsoft.com/ja-jp/PowerShell/module/microsoft.powershell.utility/new-temporaryfile
  $TempDir = New-TemporaryFile|ForEach-Object{
    # New-TemporaryFile にて作成した一時ファイルを削除して、同名の一時作業用ディレクトリを作成する。
    Remove-Item $_; New-Item $_ -ItemType Directory -Force -ErrorAction Continue;
  };
  # cygwin/msys2 環境用のパス入力用文字列
  $TempDirCyg = "`$(cygpath -au $($TempDir.FullName -replace "\\","/"))";
  if(-not (Test-Path $o.BuildDir)){
    New-Item $o.BuildDir -ItemType Directory -Force -ErrorAction Continue;
  }
  Set-Item Env:MSYSTEM $(if ($o.Cpu -ne 'NO_SSE') { 'MINGW64' } else { 'MINGW32' });
  $MinGW = if ($o.Cpu -ne 'NO_SSE') { '-mingw64' } else { '-mingw32' };
  $log = $null;
  msys2_shell.cmd -here -defterm -no-start $MinGW -lc "nice $($o.Make) -f $($o.Makefile) -j$($o.Jobs) $($o.Target) YANEURAOU_EDITION=$($o.Edition) COMPILER=$($o.Compiler) OS=$($o.Os) TARGET_CPU=$($o.Cpu) OBJDIR=$TempDirCyg TARGETDIR=$TempDirCyg $($o.Extra) 2>&1"|Tee-Object -Variable log;
  $log|Out-File -Encoding utf8 -Force (Join-Path $o.BuildDir "$($o.BuildName)-$($o.Target)-$($o.Compiler)-$($o.Cpu.ToLower()).log");
  Copy-Item (Join-Path $TempDir YaneuraOu-by-gcc.exe) (Join-Path $o.BuildDir "$($o.BuildName)-$($o.Target)-$($o.Compiler)-$($o.Cpu.ToLower()).exe") -Force;
  msys2_shell.cmd -here -defterm -no-start $MinGW -lc "$($o.Make) -f $($o.Makefile) clean YANEURAOU_EDITION=$($o.Edition) OBJDIR=$TempDirCyg TARGETDIR=$TempDirCyg";
  $TempDir|Where-Object{ Test-Path $_ }|Remove-Item -Recurse;
  Pop-Location;
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
  $TGOBJS|ForEach-Object{
    MakeExec($_);
  };
} else {
  # PowerShell 7以上 であればビルドを並列実行する、並列実行数は
  #   1-4 論理プロセッサ: 2並列
  #   5-9 論理プロセッサ: 3並列
  #   10-14 論理プロセッサ: 4並列
  #   15-18 論理プロセッサ: 5並列
  #   32-35 論理プロセッサ: 9並列
  #   64-67 論理プロセッサ: 17並列
  #   128-131 論理プロセッサ: 33並列
  #   256-259 論理プロセッサ: 65並列
  $ThLimit = [int][Math]::Ceiling([Math]::Sqrt([Math]::Pow($env:NUMBER_OF_PROCESSORS / 4, 2) + 3));
  $MakeExecDef = $function:MakeExec.ToString();
  $TGOBJS|ForEach-Object -ThrottleLimit $ThLimit -Parallel {
    $function:MakeExec = $using:MakeExecDef;
    MakeExec($_);
  };
}
