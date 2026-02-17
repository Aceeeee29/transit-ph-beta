import 'dart:io';
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/location.dart';
import '../services/media_service.dart';

class CreatePostDialog extends StatefulWidget {
  final Function(Post) onPostCreated;
  final String currentUserName;

  const CreatePostDialog({
    super.key,
    required this.onPostCreated,
    required this.currentUserName,
  });

  @override
  State<CreatePostDialog> createState() => _CreatePostDialogState();
}

class _CreatePostDialogState extends State<CreatePostDialog> {
  final TextEditingController _contentController = TextEditingController();
  PostCategory _selectedCategory = PostCategory.discussion;
  bool _anonymous = false;
  final List<File> _selectedImages = [];
  File? _selectedVideo;
  Location? _taggedLocation;
  final List<String> _taggedUsers = [];
  String? _routeId;

  void _createPost() {
    if (_contentController.text.isEmpty) return;

    final post = Post(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userName: _anonymous ? null : widget.currentUserName,
      userEmail:
          _anonymous ? null : 'user@example.com', // Replace with actual user
      anonymous: _anonymous,
      content: _contentController.text,
      type:
          _selectedVideo != null
              ? PostType.video
              : _selectedImages.isNotEmpty
              ? PostType.image
              : PostType.text,
      category: _selectedCategory,
      timestamp: DateTime.now(),
      imageUrls:
          _selectedImages
              .map((file) => file.path)
              .toList(), // In real app, upload to server
      videoUrl: _selectedVideo?.path, // In real app, upload to server
      taggedLocation: _taggedLocation,
      taggedUsers: _taggedUsers,
      routeId: _routeId,
    );

    widget.onPostCreated(post);
    Navigator.of(context).pop();
  }

  Future<void> _pickImage() async {
    final image = await MediaService.pickImageFromGallery();
    if (image != null) {
      setState(() {
        _selectedImages.add(image);
      });
    }
  }

  Future<void> _takePhoto() async {
    final image = await MediaService.takePhoto();
    if (image != null) {
      setState(() {
        _selectedImages.add(image);
      });
    }
  }

  Future<void> _pickVideo() async {
    final video = await MediaService.pickVideoFromGallery();
    if (video != null) {
      setState(() {
        _selectedVideo = video;
      });
    }
  }

  Future<void> _recordVideo() async {
    final video = await MediaService.recordVideo();
    if (video != null) {
      setState(() {
        _selectedVideo = video;
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _removeVideo() {
    setState(() {
      _selectedVideo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Post'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                hintText: 'What\'s on your mind?',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            // Media upload button
            Center(
              child: PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'gallery':
                      _pickImage();
                      break;
                    case 'camera':
                      _takePhoto();
                      break;
                    case 'video':
                      _pickVideo();
                      break;
                    case 'record':
                      _recordVideo();
                      break;
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(
                        value: 'gallery',
                        child: Row(
                          children: [
                            Icon(Icons.photo_library, size: 20),
                            SizedBox(width: 8),
                            Text('Gallery'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'camera',
                        child: Row(
                          children: [
                            Icon(Icons.camera_alt, size: 20),
                            SizedBox(width: 8),
                            Text('Camera'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'video',
                        child: Row(
                          children: [
                            Icon(Icons.video_library, size: 20),
                            SizedBox(width: 8),
                            Text('Video'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'record',
                        child: Row(
                          children: [
                            Icon(Icons.videocam, size: 20),
                            SizedBox(width: 8),
                            Text('Record'),
                          ],
                        ),
                      ),
                    ],
                child: ElevatedButton.icon(
                  onPressed: null, // Handled by PopupMenuButton
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Add Media'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade100,
                    foregroundColor: Colors.blue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Display selected images
            if (_selectedImages.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: FileImage(_selectedImages[index]),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.red,
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            // Display selected video
            if (_selectedVideo != null)
              Stack(
                children: [
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black,
                    ),
                    child: const Center(
                      child: Text(
                        'Video Selected',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: _removeVideo,
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.red,
                        child: Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            DropdownButton<PostCategory>(
              value: _selectedCategory,
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                });
              },
              items:
                  PostCategory.values.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(switch (category) {
                        PostCategory.discussion => 'Discussion',
                        PostCategory.live => 'Questions',
                        PostCategory.underReview => 'Tips',
                        PostCategory.routeUpdate => 'Route Update',
                        PostCategory.delayReport => 'Delay Report',
                        PostCategory.safetyAlert => 'Safety Alert',
                        PostCategory.recommendation => 'Recommendation',
                        _ => 'Unknown',
                      }),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tag a location (route or stop)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _taggedLocation =
                      value.isNotEmpty
                          ? Location(id: value, name: value, type: 'route')
                          : null;
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Anonymous'),
                Switch(
                  value: _anonymous,
                  onChanged: (value) {
                    setState(() {
                      _anonymous = value;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _createPost,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Post', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
