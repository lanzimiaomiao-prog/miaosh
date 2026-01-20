这是一个alpine一键脚本库
该脚本是找gemini ai搓的
安装的文件都是从官方仓库获取

确保你安装了curl

```
apk  update
apk add curl
```
**reality**

```
curl -o install_xray.sh -fSL https://github.com/lanzimiaomiao-prog/miaosh/raw/main/install_xray.sh  && sh install_xray.sh
```
**hysteria2**
```
curl -o install_hy2.sh -fSL https://github.com/lanzimiaomiao-prog/miaosh/raw/main/install_hy2.sh && sh install_hy2.sh
```

覆盖安装: 
```
sh install_hy2.sh
```
保留配置更新:
```
sh install_hy2.sh update
```
卸载程序: 
```
sh install_hy2.sh uninstall
```




覆盖安装: 
```
sh install_xray.sh
```
卸载程序: 
```
sh install_xray.sh update
```
保留配置更新:
```
sh install_xray.sh uninstall
```
