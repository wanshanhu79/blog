## 一、各种不同后缀名表示的含义
 X.509是常见通用的证书格式。所有的证书都符合为Public Key Infrastructure (PKI) 制定的 ITU-T X509 国际标准。  

*  .pem : Privacy Enhanced Mail，以 -----BEGIN........开头，以 -----END......结束，内容是BASE64编码
*  .csr : 证书签名请求，这个并不是证书，核心内容是公钥加用户信息
*  .crt : 已经签名的证书
*  .der : Distinguished Encoding Rules ，证书， 二进制格式，不可读
* .p12 :  = CER文件  + 私钥

PS : 系统自带库 公钥文件支持 .der 格式的，私钥支持 .p12 格式

## 二、openssl 命令生成 rsa 私钥共钥及证书
命令行 切换到相应的文件夹 
```
$ openssl     //开启openssl命令
$ genrsa -out rsa_private_key.pem 1024         //生成私钥
$ rsa -in rsa_private_key.pem -pubout -out rsa_public_key.pem
 writing RSA key           //生成公钥
$ pkcs8 -topk8 -in rsa_private_key.pem -out pkcs8_rsa_private_key.pem -nocrypt         //对私钥进行PKCS#8编码，并且不设置密码 
$ req -new -key rsa_private_key.pem -out rsa_cert.csr         //根据私钥创建证书请求，需要填写相关信息
$ x509 -req -days 3650 -in rsa_cert.csr -signkey rsa_private_key.pem -out rsa_cert.crt             //生成证书并且签名，有效期10年
$ x509 -outform der -in rsa_cert.crt -out rsa_cert.der           //转换格式-将 PEM 格式文件转换成 DER 格式
$ pkcs12 -export -out p.p12 -inkey rsa_private_key.pem -in rsa_cert.crt         //导出P12文件，需要设置密码
$ exit       //退出openssl命令
```

##三、加密的方式及开启方法
加密的方式主要分为两种 
* 1、系统的 *<Security/Security.h>* 中的 SecKeyRef
共钥可以通过后缀名为 .per 的文件创建，也可以通过共钥字符串创建。
私钥通过后缀名为 .p12 的文件创建，需要密码，也可以通过私钥字符串创建。
共钥加密，私钥解密，私钥签名，共钥验证。
* 2、第三方的 *openssl* 中的 RSA
共钥可以通过后缀名为 .pem 的文件创建，也可以通过共钥字符串创建。
私钥通过后缀名为 .pem的文件创建，也可以通过私钥字符串创建。
共钥加密，私钥解密，私钥签名，共钥验证。也可以私钥加密，共钥解密。

##四、实现过程中踩过的坑
* 1、对于加密的内容需要转义，并且长度不能超出密钥长度减去11字符，如果过长需要自己截取分段加密。
* 2、SecKeyRef 加解密中参数的坑
```
/*!
 @function SecKeyEncrypt
 @abstract Encrypt a block of plaintext.
 @param key Public key with which to encrypt the data.
 @param padding See Padding Types above, typically kSecPaddingPKCS1.
 @param plainText The data to encrypt.
 @param plainTextLen Length of plainText in bytes, this must be less
 or equal to the value returned by SecKeyGetBlockSize().
 @param cipherText Pointer to the output buffer.
 @param cipherTextLen On input, specifies how much space is available at
 cipherText; on return, it is the actual number of cipherText bytes written.
 @result A result code. See "Security Error Codes" (SecBase.h).
 @discussion If the padding argument is kSecPaddingPKCS1 or kSecPaddingOAEP,
 PKCS1 (respectively kSecPaddingOAEP) padding will be performed prior to encryption.
 If this argument is kSecPaddingNone, the incoming data will be encrypted "as is".
 kSecPaddingOAEP is the recommended value. Other value are not recommended
 for security reason (Padding attack or malleability).

 When PKCS1 padding is performed, the maximum length of data that can
 be encrypted is the value returned by SecKeyGetBlockSize() - 11.

 When memory usage is a critical issue, note that the input buffer
 (plainText) can be the same as the output buffer (cipherText).
 */
OSStatus SecKeyEncrypt(
                       SecKeyRef           key,
                       SecPadding          padding,
                       const uint8_t		*plainText,
                       size_t              plainTextLen,
                       uint8_t             *cipherText,
                       size_t              *cipherTextLen)
__OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_2_0);
```
```
/*!
 @function SecKeyDecrypt
 @abstract Decrypt a block of ciphertext.
 @param key Private key with which to decrypt the data.
 @param padding See Padding Types above, typically kSecPaddingPKCS1.
 @param cipherText The data to decrypt.
 @param cipherTextLen Length of cipherText in bytes, this must be less
 or equal to the value returned by SecKeyGetBlockSize().
 @param plainText Pointer to the output buffer.
 @param plainTextLen On input, specifies how much space is available at
 plainText; on return, it is the actual number of plainText bytes written.
 @result A result code. See "Security Error Codes" (SecBase.h).
 @discussion If the padding argument is kSecPaddingPKCS1 or kSecPaddingOAEP,
 the corresponding padding will be removed after decryption.
 If this argument is kSecPaddingNone, the decrypted data will be returned "as is".

 When memory usage is a critical issue, note that the input buffer
 (plainText) can be the same as the output buffer (cipherText).
 */
OSStatus SecKeyDecrypt(
                       SecKeyRef           key,                /* Private key */
                       SecPadding          padding,			/* kSecPaddingNone,
                                                             kSecPaddingPKCS1,
                                                             kSecPaddingOAEP */
                       const uint8_t       *cipherText,
                       size_t              cipherTextLen,		/* length of cipherText */
                       uint8_t             *plainText,	
                       size_t              *plainTextLen)		/* IN/OUT */
__OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_2_0);
```

```
//加密实现
- (NSData *)encryptData:(NSData *)data
                      withKeyType:(QKeyType)keyType {
    SecKeyRef keyRef = _pubSecKeyRef;
    if (keyRef == NULL) {
        NSAssert(NO, @"对应的秘钥不在");
        return nil;
    }
    
    int dataLength = (int)data.length;
    int blockSize = (int)SecKeyGetBlockSize(keyRef) * sizeof(uint8_t);
 int maxLen =  blockSize;
    if (padding == kSecPaddingPKCS1) {
/**When PKCS1 padding is performed, the maximum length of data that can
 be encrypted is the value returned by SecKeyGetBlockSize() - 11. */
        maxLen -= 11;
    }
    int count = (int)ceil(dataLength * 1.0 / maxLen); // 计算出来的count达不到预期，ceil没有实现向上取整，发现是整数相除
//还有除数一定是一次处理的数据数，照这个错误找了好久
    
    NSMutableData *encryptedData = [[NSMutableData alloc] init] ;
    uint8_t* cipherText = (uint8_t*)malloc(blockSize);
    
    for (int i = 0; i < count; i++) {
        NSUInteger bufferSize = MIN(maxLen, dataLength - i * maxLen);
        NSData *inputData = [data subdataWithRange:NSMakeRange(i * maxLen, bufferSize)];
        bzero(cipherText, blockSize);//初始化
        size_t outlen = blockSize; //刚开始直接用的maxLen ，一直错误，
        
        OSStatus status = SecKeyEncrypt(keyRef,
                                        kSecPaddingPKCS1,
                                        (const uint8_t *)[inputData bytes],
                                        bufferSize,
                                        cipherText,
                                        &outlen);
        if (status == errSecSuccess) {//errSecSuccess == 0
            [encryptedData appendBytes:cipherText length:outlen];
        }else{
            free(cipherText);
            cipherText = NULL;
            return nil;
        }
    }
    free(cipherText);
    cipherText = NULL;
    
    return encryptedData;
}
//解密数据
- (NSData *)decryptEncryptedData:(NSData *)encryptedData
                               withKeyType:(QKeyType)keyType {
    SecKeyRef keyRef = _priSecKeyRef;
    if (keyRef == NULL) {
        NSAssert(NO, @"对应的秘钥不在");
        return nil;
    }
    int dataLength = (int)encryptedData.length;
    int blockSize = (int)SecKeyGetBlockSize(keyRef) * sizeof(uint8_t);
    int maxLen = blockSize ; //这个地方不需要减11字符
    int count = (int)ceil(dataLength * 1.0 / blockSize);
    
    NSMutableData *decryptedData = [[NSMutableData alloc] init] ;
    UInt8 *outbuf = malloc(blockSize);
    for (int i = 0; i < count; i++) {
        NSUInteger bufferSize = MIN(maxLen, dataLength - i * maxLen);
        NSData *inputData = [encryptedData subdataWithRange:NSMakeRange(i * maxLen, bufferSize)];
        bzero(outbuf, blockSize);//初始化
        size_t outlen = blockSize;
        
        OSStatus status = SecKeyDecrypt(keyRef,
                                        secPadding(),
                                        (const uint8_t *)[inputData bytes],
                                        bufferSize,
                                        outbuf,
                                        &outlen);
        if (status == errSecSuccess) {
            [decryptedData appendBytes:outbuf length:outlen];
        }else{
            free(outbuf);
            outbuf = NULL;
            return nil;
        }
    }
    
    free(outbuf);
    outbuf = NULL;
    return decryptedData;
}
```

* 3、三方 RSA 类加密中遇到的坑
```
PEM_read_RSAPrivateKey(<#FILE *fp#>, <#RSA **x#>, <#pem_password_cb *cb#>, <#void *u#>)
```
通过  .pem 文件创建 RSA 时，按照这个函数是可以传入密码，对c不熟，但找了很久才找到 ，别人怎么用的
```
int pass_cb(char *buf, int size, int rwflag, void* password) {
    snprintf(buf, size, "%s", (char*) password);
    return (int)strlen(buf);
}
```
但有密码的 .pem 文件仍然创建 RSA 失败，待后续继续努力。

```
- (NSData *)encryptData:(NSData *)data
                      withKeyType:(QKeyType)keyType {
    RSA *rsa = [self rsaForKey:keyType];
    
    if (rsa == NULL) {
        NSAssert(NO, @"对应的秘钥不在");
        return nil;
    }
    QRSA_PADDING_TYPE type = [self current_PADDING_TYPE];
    NSUInteger length = [self sizeOfRSA_PADDING_TYPE:type andRSA:rsa] * 1.0;
    NSUInteger dataLength = data.length;
    int count = (int)ceil(dataLength * 1.0 / length);
    
    int status;// 处理后的数据长度
    char *encData = (char *)malloc(length);
    NSMutableData *encryptedData = [[NSMutableData alloc] init] ;
    for (int i = 0; i < count; i++) {
        NSUInteger bufferSize = MIN(length, dataLength - i * length);
        NSData *inputData = [data subdataWithRange:NSMakeRange(i * length, bufferSize)];
        bzero(encData, length);//初始化
        
        switch (keyType) {
            case QKeyTypePublic:
                status = RSA_public_encrypt((int)bufferSize,
                                            (unsigned char *)[inputData bytes],
                                            (unsigned char *)encData,
                                            _pubRSA,
                                            type);
                break;
                
            case QKeyTypePrivate:
                status = RSA_private_encrypt((int)bufferSize,
                                             (unsigned char*)[inputData bytes],
                                             (unsigned char*)encData,
                                             _priRSA,
                                             type);
                break;
        }
        
        if (status > 0){//如果失败 status 为 -1 判断成功只能用 >0 
            [encryptedData appendBytes:encData length:status];
           
        }else{
            if (encData) {
                free(encData);
            }
            return nil;
        }
    }
    if (encData){
        free(encData);
    }
    return encryptedData;
}
```
* 4、SecKeyRef 签名与验证不支持 MD5

## 五、感谢
同一组密钥创建的  SecKeyRef 与 RSA 可以互相加解密。

在代码实现过程中，搜了不少代码参考，有些是直接借用，花了几天时间，本文写的代码整体实现后，借鉴的文章链接不能在此一一列举，非常感谢他们。

## 加密与签名
PS：补充，2018年3月23日
**加密**：是对数据进行机密性保护；有三种方式：对称加密，公钥加密，私钥加密。三种方法只靠其中任意一种都有不可容忍的缺点，因此将它们结合使用。主要经过以下几个过程：
* 当信息发送者需要发送信息时，首先生成一个对称密钥，用该对称密钥加密要发送的报文；
* 信息发送者用信息接收者的公钥加密上述对称密钥；
* 信息发送者将第一步和第二步的结果结合在一起传给信息接收者，称为数字信封；
* 信息接收者使用自己的私钥解密被加密的对称密钥，再用此对称密钥解密被发送方加密的密文，得到真正的原文。

**签名**：主要用于身份验证；保证数据的完整性、一致性以及数据来源的可靠性。主要经过以下几个过程：
* 信息发送者使用一单向散列函数（HASH函数）对信息生成信息摘要；
* 信息发送者使用自己的私钥签名信息摘要；
* 信息发送者把信息本身和已签名的信息摘要一起发送出去；
* 信息接收者通过使用与信息发送者使用的同一个单向散列函数（HASH函数）对接收的信息本身生成新的信息摘要，再使用信息发送者的公钥对信息摘要进行验证，以确认信息发送者的身份和信息是否被修改过。
加密是可逆的，签名是不可逆。私钥只能用来签名，公钥用来验证签名。
