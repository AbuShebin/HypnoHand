import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flexivideoplayer/flexivideoplayer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hypnohand/core/constants/firebase_constants.dart';
import 'package:hypnohand/model/courseModel.dart';
import 'package:hypnohand/core/theme/pallete.dart';
import 'package:hypnohand/core/utils.dart';
import 'package:hypnohand/feature/single_course/screen/payMent.dart';
import 'package:hypnohand/feature/single_course/screen/videoscreenplay.dart';
import 'package:hypnohand/model/razorpay_Response.dart';
import 'package:hypnohand/model/usermodel.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/global_variables/global_variables.dart';
import 'razor_credentials.dart' as razorCredentials;
import 'package:http/http.dart' as http;

class CourseSingleView extends ConsumerStatefulWidget {
  final CourseModel courseModel;
  const CourseSingleView({super.key, required this.courseModel});

  @override
  ConsumerState<CourseSingleView> createState() => _CourseSingleViewState();
}

class _CourseSingleViewState extends ConsumerState<CourseSingleView> {
  late VideoPlayerController _videoPlayerController1;
  FlexiController? _FlexiController;
  bool isSourceError = false;
    late Razorpay _razorpay;
  final paymentStatusProvider = StateProvider((ref) => 'Not Initiated');

  CollectionReference get _razorpaySuccess =>
      FirebaseFirestore.instance.collection(FirebaseConstants.razorpaySuccess);

  CollectionReference get _courses =>
      FirebaseFirestore.instance.collection(FirebaseConstants.courses);

  TextEditingController amtController = TextEditingController();
  String? coursePrice;
  
  @override
  void initState() {
    super.initState();
     _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, handlePaymentSucces);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, handleExternalWallet);
    coursePrice =widget.courseModel.ogprice+'00';
    initializePlayer();
  }

   onPaymentSuccess(
      {required String price,
      required double discount,
      required String courseName,
      required String subName,
      required Map<dynamic, dynamic> response}) {
    print(price);
    print('ente price------------');
    RazorPayResponseModel data = RazorPayResponseModel(
        price: price,
        discount: discount,
        courseName: courseName,
        subName: subName,
        response: response,
        purchaseDate: DateTime.now());
    _razorpaySuccess.add(data.toMap());

    List _newStudentList = widget.courseModel.listofstudents;
    _newStudentList.add(userModel!.id!);
    print(_newStudentList);
    print('new list----------');

    CourseModel _courseUpdateData =
        coursemodell!.copyWith(listofstudents: _newStudentList);

    _courses
        .doc(widget.courseModel.docid)
        .update(_courseUpdateData.toMap())
        .then((value) {
      showSnackbar(context, 'Courses are now unlocked');
    });
  }

  // create order
  void createOrder() async {
    String username =
        razorCredentials.keyId; //key id you get from razorpay from settings
    String password = razorCredentials.keySecret; //this tooo
    String basicAuth =
        'Basic ${base64Encode(utf8.encode('$username:$password'))}'; //this api required basic auth user and pass.

    Map<String, dynamic> body = {
      "amount": coursePrice,
      "currency": "INR",
      "receipt": "rcptid_11"
    };

    var res = await http.post(
      Uri.https(
          "api.razorpay.com", "v1/orders"), //https://api.razorpay.com/v1/orders
      headers: <String, String>{
        "Content-Type": "application/json",
        'authorization': basicAuth,
      },
      body: jsonEncode(body),
    );
    print(res.statusCode);
    print("res.statusCode----------");
    if (res.statusCode == 200) {
      ///on success move to second step checkout.
      ///in response on create order id pass it to checkout.
      openGateway(jsonDecode(res.body)['id']);
    }
    print(res.body);
  }

  openGateway(String orderId) {
    print(coursePrice);
    print("funda price===========");
    var options = {
      'key': razorCredentials.keyId,

      ///key id from razorpay
      'amount': coursePrice! ,

      ///in the smallest currency sub-unit.
      'name': 'Hypno Hand.',
      'order_id': orderId,

      /// Generate order_id using Orders API

      'description': 'Course 1  ',
      'timeout': 60 * 5,

      /// in seconds // 5 minutes

      'prefill': {
        'contact': userModel?.phoneNumber??'',
        'email': userModel?.email??'',
      },
      'external': {
        'wallets': ['paytm']
      },
    };
    _razorpay.open(options);

    ///open gateway for checkout
    ///now to check responses thats success or failed etc , you will get those in listener.
  }

  void handlePaymentSucces(PaymentSuccessResponse response) {
    ref
        .read(paymentStatusProvider.notifier)
        .update((state) => 'Payment Successfull');
    onPaymentSuccess(
        price: widget.courseModel.ogprice??'' ,
        discount: 0,
        courseName: 'course 1',
        subName: 'course 1',
        response: {});
    print(response.signature);
    print(response.paymentId);
    print(response.orderId);
    // print(response.data);

    print("success response-------------");

    ///on success we will verify signature to check authenticity

    verifySignature(
      orderId: response.orderId,
      paymentId: response.paymentId,
      signature: response.signature,
    );

    ///course purchased...
    Fluttertoast.showToast(
      msg: "payment Successfull " + response.paymentId!,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  void handlePaymentError(PaymentFailureResponse response) {
    ref
        .read(paymentStatusProvider.notifier)
        .update((state) => 'Payment Failed');
    print(response);
    print(response.message);
    // print(response.error);
    print(response.code);

    print('failure response----------------------');

    Fluttertoast.showToast(
        msg: "Payment Failed " + response.message!,
        toastLength: Toast.LENGTH_SHORT);
  }

  void handleExternalWallet(ExternalWalletResponse response) {
    print(response);
    print('external wallet response--------------');
    Fluttertoast.showToast(
        msg: "External Wallet " + response.walletName!,
        toastLength: Toast.LENGTH_SHORT);
  }

  ///i hv written php code on server side to verify signature.
  ///below fuction is to call the api.
  verifySignature({
    String? signature,
    String? paymentId,
    String? orderId,
  }) async {
    ///here we are calling post request url encoded
    Map<String, dynamic> body = {
      'razorpay_signature': signature,
      'razorpay_payment_id': paymentId,
      'razorpay_order_id': orderId,
    };

    var parts = [];
    body.forEach((key, value) {
      parts.add('${Uri.encodeQueryComponent(key)}='
          '${Uri.encodeQueryComponent(value)}');
    });
    var formData = parts.join('&');
    var res = await http.post(
      Uri.https(
        "10.0.2.2", // my ip address , localhost
        "razorpay_signature_verify.php",
      ),
      headers: {
        "Content-Type": "application/x-www-form-urlencoded", // urlencoded
      },
      body: formData,
    );

    print(res.body);
    if (res.statusCode == 200) {
      print("payment Verified--");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.body),

          ///we are showing response from signature verification api
        ),
      );
    }
  }

  Stream<CourseModel> courseStream() {
    return FirebaseFirestore.instance
        .collection(FirebaseConstants.courses)
        .doc(widget.courseModel.docid)
        .snapshots()
        .map((event) =>
            CourseModel.fromMap(event.data() as Map<String, dynamic>));
  }

  Future<void> initializePlayer() async {
    setState(() {
      isSourceError = false;
    });
    try {
      _videoPlayerController1 = VideoPlayerController.networkUrl(
          Uri.parse(widget.courseModel.demovideolink.toString()));

      await _videoPlayerController1.initialize();

      final subtitles = [
        Subtitle(
          index: 0,
          start: const Duration(seconds: 0),
          end: Duration(
              seconds: _videoPlayerController1.value.duration.inSeconds),
          text: 'Whats up? :)',
        ),
      ];

      _FlexiController = FlexiController(
        aspectRatio: 16 / 9,
        deviceOrientationsOnEnterFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight
        ],
        deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp],
        allowFullScreen: true,
        fullScreenByDefault: false,
        allowedScreenSleep: false,
        videoPlayerController: _videoPlayerController1,
        autoPlay: true,
        looping: true,
        errorBuilder: (context, errorMessage) {
          print("Error find : $errorMessage");

          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
        additionalOptions: (context) {
          return <OptionItem>[
            OptionItem(
              onTap: toggleVideo,
              iconData: Icons.live_tv_sharp,
              title: 'Toggle Video Src',
            ),
          ];
        },
        subtitle: Subtitles(subtitles),
        subtitleBuilder: (context, dynamic subtitle) => Container(
          padding: const EdgeInsets.all(10.0),
          child: subtitle is InlineSpan
              ? RichText(
                  text: subtitle,
                )
              : Text(
                  subtitle.toString(),
                  style: const TextStyle(color: Colors.white),
                ),
        ),

        hideControlsTimer: const Duration(seconds: 3),

        // Try playing around with some of these other options:
        isBrignessOptionDisplay: true,
        isVolumnOptionDisplay: true,

        cupertinoProgressColors: FlexiProgressColors(
          playedColor: Colors.red,
          handleColor: Colors.red,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.white.withOpacity(0.5),
        ),
      );

      setState(() {});
    } catch (exception) {
      setState(() {
        isSourceError = true;
      });
      print("exception : $exception");
    }
  }

  Future<void> toggleVideo() async {
    await initializePlayer();
  }

  @override
  void dispose() {
    _FlexiController!.dispose();
    _videoPlayerController1.dispose();
    _razorpay.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    h = MediaQuery.of(context).size.height;
    w = MediaQuery.of(context).size.width;
    return SafeArea(
      child: Scaffold(
        backgroundColor: Color(0xFFF8F6F4),
        body: Padding(
          padding: EdgeInsets.fromLTRB(w * 0.05, 0, w * 0.05, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: h * 0.08,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Icon(
                        CupertinoIcons.back,
                        color: Palette.blackColor,
                        size: w * 0.06,
                      ),
                    ),
                    Text(
                      widget.courseModel.coursename.toString(),
                      style: TextStyle(
                          color: Palette.blackColor,
                          fontSize: w * 0.044,
                          fontWeight: FontWeight.w500),
                    ),
                    // Icon(
                    //   Icons.more_vert_rounded,
                    //   color: Palette.blackColor,
                    //   size: w * 0.06,
                    // ),
                    SizedBox(
                      width:  w * 0.06,
                    )
                  ],
                ),
              ),
              // Text(
              //   widget.courseModel.subname,
              //   style: TextStyle(
              //       color: Palette.blackColor,
              //       fontSize: w * 0.056,
              //       fontWeight: FontWeight.w600),
              // ),
              SizedBox(height: h * 0.005),
              // Text(
              //   "Among the many techniques and tricks that one needs to hone, there are also a few skills students need to master to become a mentalist. However, apart from obtaining the skills, people need to practice and sharpen these skills to gain perfection.",
              //   style: TextStyle(
              //       color: Palette.blackColor,
              //       fontSize: w * 0.026,
              //       fontWeight: FontWeight.w300),
              // ),
              // SizedBox(height:h*0.02),
              // SizedBox(height: h * 0.02),
              Container(
                color: Colors.black,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: isSourceError
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                              Icon(
                                CupertinoIcons.exclamationmark_circle,
                                color: Colors.white,
                                size: 30,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'This video is unavailable',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 15),
                              ),
                              InkWell(
                                onTap: () {
                                  initializePlayer();
                                },
                                child: Container(
                                  height: 30,
                                  width: 100,
                                  alignment: Alignment.center,
                                  child: Text(
                                    "Reload again",
                                    style: TextStyle(
                                        color: Colors.red, fontSize: 13),
                                  ),
                                ),
                              )
                            ])
                      : _FlexiController != null
                          ?
                          // &&
                          //        _FlexiController!
                          //            .videoPlayerController.value.isInitialized
                          //        ?
                          Flexi(
                              controller: _FlexiController!,
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                  CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.red,
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    'Loading',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 15),
                                  ),
                                ]),
                ),
              ),
              StreamBuilder<CourseModel>(
                  stream: courseStream(),
                  builder: (context, snapshot) {
                    CourseModel? data = snapshot.data;
                    if (snapshot.hasData) {
                      return data!.listofstudents.contains(userModel!.id)
                          ? SizedBox()
                          : Container(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: h * 0.02),
                                  Text(
                                    'Rs.${widget.courseModel.ogprice}.00',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  SizedBox(
                                    width: w,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        createOrder();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Palette.primaryColor,
                                      ),
                                      child: const Text('Buy Now',
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                    } else {
                      return SizedBox();
                    }
                  }),

              SizedBox(height: h * 0.02),
              Expanded(
                child: StreamBuilder<CourseModel>(
                    stream: courseStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        var data = snapshot.data;
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: widget.courseModel.listofvideo.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: h * 0.02),
                              child: GestureDetector(
                                onTap: () {
                                data!.listofstudents.contains(userModel!.id)
                                    ? Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => VideoScreenPlay(
                                            videolink: widget.courseModel
                                                    .listofvideo[index]
                                                ['videolink'],
                                          ),
                                        ))
                                    : showSnackbar(context,
                                        'You have to purchase the course first');
                              },
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          height: h * 0.11,
                                          width: w * 0.3,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(w * 0.02),
                                            image: const DecorationImage(
                                                image: AssetImage(
                                                    "assets/Banner1.jpg"),
                                                fit: BoxFit.cover),
                                          ),
                                        ),
                                        widget.courseModel.listofstudents
                                                .contains(userModel!.id)
                                            ? SizedBox()
                                            : Container(
                                                height: h * 0.11,
                                                width: w * 0.3,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          w * 0.02),
                                                  color: Colors.black54,
                                                ),
                                                child: Icon(

                                                  Icons.lock_outline_rounded,
                                                  color: Colors.white,
                                                ),
                                              )
                                      ],
                                    ),
                                    SizedBox(width: w * 0.02),
                                    SizedBox(
                                      width: w * 0.55,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: [
                                          Text(
                                            "How to be Mentalist",
                                            style: TextStyle(
                                              color: Palette.blackColor,
                                              fontSize: w * 0.04,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            "Tutor: Nafih",
                                            style: TextStyle(
                                              color: Palette.blackColor,
                                              fontSize: w * 0.038,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                          Text(
                                            "Level ${index + 1}",
                                            style: TextStyle(
                                              color: Palette.blackColor,
                                              fontSize: w * 0.03,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                          Text(
                                            "The class is about to teach them the tricks that one needs to hone. There are also a few skills students need to master to become a mentalist",
                                            style: TextStyle(
                                              color: Palette.blackColor,
                                              fontSize: w * 0.02,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      } else {
                        return CircleAvatar();
                      }
                    }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
